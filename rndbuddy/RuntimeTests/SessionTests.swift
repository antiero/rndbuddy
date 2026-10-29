import Foundation
import SwiftData
import Testing
@testable import rndbuddy

@Suite(.serialized) @MainActor struct SessionTests {
    func fixture() -> (DeviceSession, FakeMIDITransport) {
        let transport = FakeMIDITransport()
        transport.endpoints = [MIDIEndpoint(id: 77, name: "RND test", source: 1, destination: 2)]
        let session = DeviceSession(transport: transport,preferences:nil)
        session.selectFirmware(.jg023)
        transport.inject(RNDProtocolCodec.message(0x21,[0,120,0,0,6]))
        return (session,transport)
    }
    @Test func connectingOnlyReadsHardware() {
        let transport = FakeMIDITransport()
        transport.endpoints = [MIDIEndpoint(id:77,name:"RND test",source:1,destination:2)]
        let session = DeviceSession(transport:transport,preferences:nil)
        #expect(session.connected)
        #expect(transport.sent.map(\.bytes) == [RNDProtocolCodec.message(0x7E),RNDProtocolCodec.message(0x18)])
        session.generate()
        #expect(transport.sent.count == 2)
    }
    @Test func twoOwnersOfOneNoteReleaseOnlyOnLastContact() {
        let (session,transport) = fixture()
        let baseline = transport.sent.count
        session.note(source:"a",note:60,track:0)
        session.note(source:"b",note:60,track:0)
        session.note(source:"a",note:nil,track:0)
        #expect(transport.sent.count == baseline+1)
        session.note(source:"b",note:nil,track:0)
        #expect(Array(transport.sent.suffix(2)).map(\.bytes) == [[0x91,60,90],[0x81,60,0]])
    }
    @Test func demoNeverSendsHardwareMessages() {
        let (session,transport) = fixture()
        session.startDemo(); let count = transport.sent.count
        session.generate(); session.setScale(3); session.setControl(7,value:50)
        session.note(source:"touch",note:60,track:0); session.releaseAll()
        #expect(transport.sent.count == count)
        session.connect(nil)
    }
    @Test func backgroundAndModeSwitchReleaseNotes() {
        let (session,transport) = fixture()
        let controller = PerformanceController(session:session)
        controller.mode = .play
        controller.update([Contact(id:"touch",x:0.4,y:0.5)])
        controller.background()
        #expect(transport.sent.last?.bytes.first == 0x81)
        #expect(controller.contacts.isEmpty)
        #expect(!controller.armed)
    }
    @Test func reportedGlobalDumpDoesNotOverwriteRequestedEditsDuringRecall() async {
        let (session,transport) = fixture()
        let patch = PatchSnapshot(seed:42,firmware:.jg023,tempo:105,root:4,scale:1,type:0)
        session.recall(patch)
        await Task.yield()
        #expect(session.recalling)
        transport.inject(RNDProtocolCodec.message(0x21,[0,120,0,0,6]))
        try? await Task.sleep(for:.milliseconds(180))
        #expect(!session.recalling)
        #expect(session.snapshot.seed == 42)
        #expect(session.snapshot.tempo == 105)
        let messages = transport.sent.map(\.bytes)
        let hold = messages.firstIndex(of:RNDProtocolCodec.message(0x1B,[1]))
        let release = messages.firstIndex(of:RNDProtocolCodec.message(0x1B,[0]))
        #expect(hold != nil && release != nil && hold! < release!)
    }
    @Test func libraryLocalSaveEditDuplicateDelete() throws {
        let library = try LibraryStore(inMemory:true)
        var patch = PatchDocument(name:"Test",snapshot:PatchSnapshot(seed:42,firmware:.jg023))
        library.save(patch)
        #expect(library.patches.count == 1)
        patch.name = "Edited"; library.save(patch)
        #expect(library.patches.count == 1)
        #expect(library.patches.first?.name == "Edited")
        library.save(patch,newIdentity:true)
        #expect(library.patches.count == 2)
        library.remove(patch.id)
        if library.patches.count != 1 {
            for row in try library.container.mainContext.fetch(FetchDescriptor<SavedPatch>()) {
                print("Revision",row.recordID,row.modifiedAt.timeIntervalSince1970,row.tombstone,row.revisionID)
            }
            print("Library error",library.error ?? "none")
        }
        #expect(library.patches.count == 1)
    }
}

@MainActor struct ConnectionLifecycleTests {
    @Test func reconnectsAfterHotplugButHonoursManualDisconnect() {
        let transport=FakeMIDITransport()
        let endpoint=MIDIEndpoint(id:77,name:"RND test",source:1,destination:2)
        transport.endpoints=[endpoint]
        let session=DeviceSession(transport:transport,preferences:nil)
        #expect(session.connected)
        transport.endpoints=[]; transport.refresh()
        #expect(!session.connected)
        transport.endpoints=[endpoint]; transport.refresh()
        #expect(session.connectedID == endpoint.id)
        session.connect(nil); transport.refresh()
        #expect(!session.connected)
    }
}
