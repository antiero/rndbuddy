import Foundation
import Observation

@MainActor @Observable final class AppModel {
    let session: DeviceSession
    let performance: PerformanceController
    let pixels: PixelsHost
    let audio = AudioMonitor()
    let hands = HandInput()
    let motion = MotionInput()
    let library: LibraryStore?
    var startupError: String?
    var destination = AppDestination.perform
    var showMixer = false
    var showAssignments = false
    var showSave = false
    var showTakeover = false
    init() {
        let testing=NSClassFromString("XCTestCase") != nil
        let session = testing ? DeviceSession(transport:FakeMIDITransport(),preferences:nil) : DeviceSession()
        self.session = session
        performance = PerformanceController(session: session)
        pixels = PixelsHost(session: session)
        do { library = try LibraryStore(inMemory:testing) }
        catch { library = nil; startupError = "Library could not open: \(error.localizedDescription)" }
        hands.onContacts = { [weak self] contacts in
            guard let self, self.performance.method == .hands else { return }
            self.performance.update(contacts, sensor: true)
        }
        motion.onContacts = { [weak self] contacts in
            guard let self, self.performance.method == .motion else { return }
            self.performance.update(contacts, sensor: true)
        }
        if pixels.permission && !testing { pixels.load() }
        if ProcessInfo.processInfo.arguments.contains("--demo") { session.startDemo() }
    }
    func changeInput(_ method: InputMethod) {
        hands.stop(); motion.stop(); performance.method = method
    }
    func arm(_ value: Bool) {
        performance.armed = value
        if !value { hands.stop(); motion.stop(); return }
        if performance.method == .hands { Task { await hands.start(); if !performance.armed { hands.stop() } } }
        if performance.method == .motion { motion.start() }
    }
    func background() {
        hands.stop(); motion.stop(); performance.background()
        // User-started audio monitoring intentionally remains active.
    }
}
enum AppDestination: String, CaseIterable, Identifiable {
    case perform = "Perform", library = "Library", settings = "Settings"
    var id: String { rawValue }
    var symbol: String { switch self { case .perform: "slider.horizontal.3"; case .library: "square.stack"; case .settings: "gearshape" } }
}
