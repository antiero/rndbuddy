import Foundation
import Testing
@testable import rndbuddy

@MainActor struct ControlRouterTests {
    func fixture(firmware: FirmwareProfile = .jg023) -> (PerformanceController, FakeMIDITransport) {
        let (session, transport) = SessionTests().fixture()
        session.selectFirmware(firmware)
        return (PerformanceController(session: session), transport)
    }
    private func spec(_ controller: PerformanceController, _ kind: ControlKind, action: TriggerAction? = nil) -> ControlSpec {
        controller.page.controls.first { $0.kind == kind && (action == nil || $0.action == action) }!
    }

    @Test func fieldAndFaderSendIndependentCCs() {
        let (controller, transport) = fixture()
        let field = spec(controller, .xy), fader = spec(controller, .fader)
        controller.update(field.id, [Contact(id: "a", x: 1, y: 0)])
        controller.setFader(fader.id, value: 0.5)
        let ccs = transport.sent.map(\.bytes).filter { $0.first.map { $0 & 0xF0 == 0xB0 } ?? false }
        #expect(ccs.contains([0xB1, 7, 127]))   // track 1 volume from the field
        #expect(ccs.contains([0xB1, 91, 127]))  // track 1 reverb from the field
        #expect(ccs.contains([0xB0, 7, 64]))    // master volume from the fader
        #expect(controller.faderValues[fader.id] == 0.5)
        controller.setFader(fader.id, value: nil)
        #expect(controller.faderValues[fader.id] == nil)
    }
    @Test func latestControlOwnsASharedTarget() {
        let (controller, _) = fixture()
        var page = controller.page
        let a = ControlSpec(kind: .fader, title: "A", bindings: [ControlBinding(.masterVolume)])
        let b = ControlSpec(kind: .fader, title: "B", bindings: [ControlBinding(.masterVolume)])
        page.controls = [a, b]; controller.pages = [page]
        controller.setFader(a.id, value: 0.2)
        #expect(!controller.isOverridden(a))
        controller.setFader(b.id, value: 0.9)
        #expect(controller.isOverridden(a))
        #expect(!controller.isOverridden(b))
    }
    @Test func firmwareGatedTargetsSendNothing() {
        let (controller, transport) = fixture(firmware: .official14)
        let tone = ControlSpec(kind: .fader, title: "Tone", bindings: [ControlBinding(.tone)])
        let freeze = ControlSpec(kind: .trigger, title: "Freeze", action: .freeze)
        controller.pages = [PerformancePage(name: "Deep", controls: [tone, freeze])]
        let before = transport.sent.count
        controller.setFader(tone.id, value: 0.7)
        controller.trigger(freeze)
        #expect(transport.sent.count == before)
    }
    @Test func pageSwitchReleasesHeldNotes() {
        let (controller, transport) = fixture()
        controller.mode = .play
        controller.playYAxis = .velocity
        controller.update([Contact(id: "a", x: 0.5, y: 0.5)])
        #expect(transport.sent.last?.bytes.first == 0x91)
        controller.pageIndex = 1
        #expect(transport.sent.last?.bytes.first == 0x81)
        #expect(controller.contacts.isEmpty)
    }
    @Test func keysOnlySoundInPlayModeAndRelease() {
        let (controller, transport) = fixture()
        controller.pageIndex = controller.pages.firstIndex { $0.name == "Keys" }!
        let keys = spec(controller, .keys)
        let before = transport.sent.count
        controller.key(keys.id, degree: 0, down: true)
        #expect(transport.sent.count == before)
        controller.mode = .play
        controller.key(keys.id, degree: 0, down: true)
        #expect(transport.sent.last?.bytes.first == 0x91)
        #expect(controller.pressedKeys[keys.id] == [0])
        controller.key(keys.id, degree: 0, down: false)
        #expect(transport.sent.last?.bytes.first == 0x81)
        #expect(controller.pressedKeys[keys.id]?.isEmpty ?? true)
    }
    @Test func triggersActOnTheSelectedTrackAndHold() {
        let (controller, _) = fixture()
        controller.pageIndex = controller.pages.firstIndex { $0.name == "Swell" }!
        controller.session.selectedTrack = 2
        let mute = spec(controller, .trigger, action: .mute)
        controller.trigger(mute)
        #expect(controller.session.snapshot.tracks[2].muted)
        #expect(controller.isOn(mute))
        controller.pageIndex = 0
        let hold = spec(controller, .trigger, action: .hold)
        controller.trigger(hold)
        #expect(controller.held)
    }
    @Test func mappingBridgeEditsTheFirstField() {
        let (controller, _) = fixture()
        var mapping = controller.mapping
        mapping.x = AxisMapping(target: .masterReverb, minimum: 0.1, maximum: 0.9)
        controller.mapping = mapping
        #expect(controller.primaryField?.bindings[0].target == .masterReverb)
        #expect(controller.primaryField?.bindings[0].sources.contains(.hands) == true)
        controller.pageIndex = controller.pages.firstIndex { $0.name == "Keys" }!
        #expect(controller.mapping.x.target == .masterReverb)
    }
}
