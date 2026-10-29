import Foundation
import Testing
@testable import rndbuddy

@MainActor struct PlayExpressionTests {
    func fixture(volume: Int? = 90) -> (PerformanceController, FakeMIDITransport) {
        let fixture = SessionTests().fixture()
        if let volume { fixture.0.setControl(7, value: volume, channel: 2) }
        let controller = PerformanceController(session: fixture.0)
        controller.mode = .play
        return (controller, fixture.1)
    }
    @Test func verticalMovementChangesVolumeWithoutRetriggeringPitch() {
        let (controller, transport) = fixture()
        controller.update([Contact(id: "a", x: 0.5, y: 0.9)])
        #expect(transport.sent.suffix(2).first?.bytes == [0xB1, 7, 13])
        #expect(transport.sent.last?.bytes.last == 127)
        let before = transport.sent.count
        controller.update([Contact(id: "a", x: 0.5, y: 0.1)])
        #expect(transport.sent.count == before + 1)
        #expect(transport.sent.last?.bytes == [0xB1, 7, 114])
        controller.update([Contact(id: "a", x: 0.5, y: 0.1)])
        #expect(transport.sent.count == before + 1)
        controller.update([])
        #expect(transport.sent.last?.bytes == [0xB1, 7, 90])
    }
    @Test func polyphonicContactsShareTheHighestVolumeAndCanReachSilence() {
        let (controller, transport) = fixture()
        controller.update([Contact(id: "a", x: 0.1, y: 1), Contact(id: "b", x: 0.8, y: 0)])
        #expect(controller.session.snapshot.tracks[0].volume == 127)
        controller.update([Contact(id: "a", x: 0.1, y: 1)])
        #expect(transport.sent.last?.bytes == [0xB1, 7, 0])
        controller.cancel()
        #expect(controller.session.snapshot.tracks[0].volume == 90)
    }
    @Test func onsetVelocityRemainsAvailableWithoutSendingVolume() {
        let (controller, transport) = fixture()
        controller.playYAxis = .velocity
        let before = transport.sent.count
        controller.update([Contact(id: "a", x: 0.5, y: 1)])
        #expect(transport.sent.last?.bytes.last == 1)
        controller.update([Contact(id: "a", x: 0.5, y: 0)])
        #expect(transport.sent.count == before + 1)
        controller.cancel()
    }
    @Test func laterMixerEditsSurviveCancellation() {
        let (controller, _) = fixture()
        controller.update([Contact(id: "a", x: 0.5, y: 0)])
        controller.session.setControl(7, value: 42, channel: 2)
        controller.cancel()
        #expect(controller.session.snapshot.tracks[0].volume == 42)
    }
    @Test func unknownOriginalVolumeIsNotReplacedWithADefault() {
        let (controller, transport) = fixture(volume: nil)
        controller.update([Contact(id: "a", x: 0.5, y: 0.2)])
        controller.update([Contact(id: "a", x: 0.5, y: 0.4)])
        controller.cancel()
        #expect(transport.sent.last?.bytes.first == 0x81)
    }
    @Test func oldMappingArchivesStillDecodeAndNewChoiceRoundTrips() throws {
        let old = Data(#"{"x":{"target":"Track volume","minimum":0,"maximum":1,"inverted":false,"smoothing":0.25,"deadZone":0.01},"y":{"target":"Track reverb","minimum":0,"maximum":1,"inverted":false,"smoothing":0.25,"deadZone":0.01}}"#.utf8)
        let decoded = try JSONDecoder().decode(PerformanceMapping.self, from: old)
        #expect(decoded.playYAxis == nil)
        var mapping = decoded; mapping.playYAxis = .velocity
        #expect(try JSONDecoder().decode(PerformanceMapping.self, from: JSONEncoder().encode(mapping)) == mapping)
    }
}
