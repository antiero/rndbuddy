import Testing
import Foundation
@testable import RNDBuddyCore

struct ProtocolTests {
    @Test func seedPackingBoundaries() {
        for seed: UInt32 in [0, 1, 127, 128, 0xA17C9203, .max] {
            let packed = RNDProtocolCodec.packed(seed)
            #expect(packed.allSatisfy { $0 < 128 })
            #expect(RNDProtocolCodec.unpack(packed[...]) == seed)
            #expect(MIDIStreamParser.valid(RNDProtocolCodec.message(0x10, packed)))
        }
    }
    @Test func firmwareProfilesDoNotShareScaleAndTypeEncoding() {
        #expect(RNDProtocolCodec.scaleCC(6, firmware: .official14) == 7)
        #expect(RNDProtocolCodec.scaleCC(6, firmware: .jg023) == 41)
        #expect(RNDProtocolCodec.typeCC(2, firmware: .official14) == 3)
        #expect(RNDProtocolCodec.typeCC(2, firmware: .jg023) == 4)
    }
    @Test func unknownFirmwareCannotEmitEngineOrTempo() {
        #expect(RNDProtocolCodec.engine(0, track: 0, firmware: .unknown) == nil)
        #expect(RNDProtocolCodec.tempo(120, firmware: .unknown, snapshot: PatchSnapshot()) == nil)
        #expect(RNDProtocolCodec.engine(0, track: 4, firmware: .jg023) == nil)
    }
    @Test func officialTempoFixture() {
        #expect(RNDProtocolCodec.tempo(300, firmware: .official14, snapshot: PatchSnapshot()) == [0xF0,0x6F,0x62,0x78,0x1D,44,2,0xF7])
    }
    @Test func jgTempoRequiresAuthenticGlobalState() {
        #expect(RNDProtocolCodec.tempo(120, firmware: .jg023, snapshot: PatchSnapshot()) == nil)
        let snapshot = PatchSnapshot(seed: 1, firmware: .jg023, root: 3, scale: 6, type: 1)
        #expect(RNDProtocolCodec.tempo(120, firmware: .jg023, snapshot: snapshot) == [0xF0,0x6F,0x62,0x78,0x21,1,120,0,3,6,0xF7])
    }
    @Test func streamAcrossPacketsWithRealtimeAndRunningStatus() {
        var parser = MIDIStreamParser()
        #expect(parser.consume([0x90,60]).isEmpty)
        #expect(parser.consume([0xF8,100,62,110]) == [[0xF8],[0x90,60,100],[0x90,62,110]])
        #expect(parser.consume([0xF0,0x6F,0x62]).isEmpty)
        #expect(parser.consume([0xF8,0x78,0x10,1]).first == [0xF8])
        #expect(parser.consume([2,0xF7]) == [[0xF0,0x6F,0x62,0x78,0x10,1,2,0xF7]])
    }
    @Test func malformedSysExDoesNotAcquireSyntheticTerminator() {
        var parser = MIDIStreamParser()
        #expect(parser.consume([0xF0,1,2,0x90,60,90]) == [[0x90,60,90]])
    }
    @Test func largeSysExPreservesEveryByte() {
        var parser = MIDIStreamParser()
        let message = [UInt8(0xF0)] + (0..<40_000).map { UInt8($0 % 128) } + [0xF7]
        var result: [[UInt8]] = []
        for index in stride(from: 0, to: message.count, by: 257) { result += parser.consume(Array(message[index..<min(message.count,index+257)])) }
        #expect(result == [message])
    }
    @Test func streamBufferIsBoundedAndRecovers() {
        var parser = MIDIStreamParser()
        #expect(parser.consume([0xF0] + Array(repeating: 1, count: MIDIStreamParser.maxSysEx + 1) + [0xF7]).isEmpty)
        #expect(parser.consume([0x90,60,90]) == [[0x90,60,90]])
    }
    @Test func messageValidation() {
        #expect(!MIDIStreamParser.valid([60,90]))
        #expect(!MIDIStreamParser.valid([0x90,60]))
        #expect(!MIDIStreamParser.valid([0xF0,0x90,0xF7]))
        #expect(MIDIStreamParser.valid([0xC0,3]))
        #expect(MIDIStreamParser.valid([0xF8]))
    }
    @Test func scaleQuantisationNeverLeavesScale() {
        for scale in 0..<20 {
            for step in 0...100 {
                let note = RNDProtocolCodec.quantizedNote(x: Double(step)/100, root: 2, scale: scale, octave: 3)
                #expect(RNDProtocolCodec.intervals[scale].contains((note-2)%12))
            }
        }
    }
    @Test func mappingInversionAndBounds() {
        var mapping = AxisMapping(target: .volume)
        mapping.minimum = 0.2; mapping.maximum = 0.8; mapping.inverted = true
        #expect(abs(mapping.mapped(0)-0.8) < 0.00001)
        #expect(abs(mapping.mapped(1)-0.2) < 0.00001)
        #expect(mapping.mapped(-5) <= 0.8)
    }
    @Test func mappingDeadZoneAndReset() {
        var engine = MappingEngine(); let mapping = AxisMapping(target: .reverb)
        #expect(engine.value(0.5, axis: mapping) == 64)
        #expect(engine.value(0.501, axis: mapping) == nil)
        engine.reset(); #expect(engine.value(1, axis: mapping) == 127)
    }
}

struct OfficialLockTests {
    @Test func packedLockFixture() throws {
        // type drone, D root, Dorian, two tracks, no engines.
        let packed: UInt32 = 2 + 3*4 + 7*52 + 2*1092
        let locks = try #require(DeviceLocks.decode(packed))
        #expect(locks.type == 1)
        #expect(locks.root == 2)
        #expect(locks.scale == 6)
        #expect(locks.tracks == 2)
        #expect(locks.messages().contains(RNDProtocolCodec.message(0x1A,[1])))
        #expect(locks.messages().contains(RNDProtocolCodec.message(0x1F,[2])))
    }
    @Test func officialEngineUsesExactASCIIName() {
        #expect(RNDProtocolCodec.engine(5,track:1,firmware:.official14) == RNDProtocolCodec.message(0x1B,[1]+Array("Plucked String".utf8)+[0]))
        #expect(DeviceLocks.decode(.max) == nil)
    }
}
