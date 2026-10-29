import Foundation
import Testing
@testable import rndbuddy

@MainActor struct StageCompletionTests {
    @Test func latestGestureKeepsOwnershipUntilRelease() {
        let (controller, transport) = ControlRouterTests().fixture()
        let a = ControlSpec(kind: .fader, title: "A", bindings: [ControlBinding(.masterVolume)])
        let b = ControlSpec(kind: .fader, title: "B", bindings: [ControlBinding(.masterVolume)])
        controller.pages = [PerformancePage(name: "Shared", controls: [a, b])]
        controller.setFader(a.id, value: 0.1)
        controller.setFader(b.id, value: 0.9)
        let count = transport.sent.count
        controller.setFader(a.id, value: 0.3)
        #expect(transport.sent.count == count)
        #expect(controller.isOverridden(a))
        controller.setFader(b.id, value: nil)
        controller.setFader(a.id, value: 0.4)
        #expect(transport.sent.count > count)
        #expect(!controller.isOverridden(a))
        controller.cancel()
        #expect(!controller.isOverridden(b))
    }
    @Test func sourceFilteringAndEditingSuppressOutput() {
        let (controller, transport) = ControlRouterTests().fixture()
        let field = ControlSpec(kind: .xy, title: "Field", bindings: [ControlBinding(.volume), ControlBinding(.reverb)])
        let fader = ControlSpec(kind: .fader, title: "Height", bindings: [ControlBinding(.masterVolume, sources: [.rightHeight])])
        controller.pages = [PerformancePage(name: "Sources", controls: [field, fader])]
        controller.armed = true
        let before = transport.sent.count
        controller.updateSensor([Contact(id: "hand", x: 0.7, y: 0.2)], source: .hands)
        #expect(transport.sent.count == before)
        controller.updateFeatures([.leftHeight: 0.9])
        #expect(transport.sent.count == before)
        controller.updateFeatures([.rightHeight: 0.5])
        #expect(transport.sent.count > before)
        controller.editing = true
        let editing = transport.sent.count
        controller.setFader(fader.id, value: 0.8)
        controller.updateFeatures([.rightHeight: 0.9])
        controller.trigger(ControlSpec(kind: .trigger, title: "Generate", action: .generate))
        #expect(transport.sent.count == editing)
    }
    @Test func sensorLossReleasesNotesWhileHeld() {
        let (controller, transport) = ControlRouterTests().fixture()
        controller.mode = .play; controller.playYAxis = .velocity; controller.armed = true
        controller.updateSensor([Contact(id: "hand", x: 0.7, y: 0.2)], source: .hands)
        #expect(transport.sent.last?.bytes.first == 0x91)
        controller.held = true
        controller.updateSensor([], source: .hands)
        #expect(transport.sent.last?.bytes.first == 0x81)
    }
    @Test func localPagesSeedAndMigrateOnce() throws {
        let store = try PageStore(inMemory: true)
        let mapping = MappingDocument(name: "Legacy", mapping: PerformanceMapping())
        let first = try store.load(mappings: [mapping])
        #expect(first.count == PerformancePage.defaults.count + 1)
        var edited = first; edited[0].name = "My page"
        try store.replace(edited)
        let second = try store.load(mappings: [mapping])
        #expect(second == edited)
        let archive = try PatchArchive.decode(JSONEncoder().encode(PatchArchive(patches: [], pages: second)))
        #expect(archive.pages == second)
        let copy = second[0].copied()
        #expect(copy.id != second[0].id)
        #expect(Set(copy.controls.map(\.id)).isDisjoint(with: second[0].controls.map(\.id)))
        try copy.validate()
    }
}
