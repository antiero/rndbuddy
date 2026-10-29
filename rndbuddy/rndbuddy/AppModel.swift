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
    var pageStore: PageStore?
    var stagePresentation = StagePresentation.normal
    let stageEditor = StageEditor()
    var editingStage = false { didSet { performance.editing = editingStage; performance.cancel() } }
    var stageLayout = LayoutClass.mac
    var stageError: String?
    var portraitFraction = UserDefaults.standard.double(forKey: "rndbuddy.stageDivider") {
        didSet { UserDefaults.standard.set(portraitFraction, forKey: "rndbuddy.stageDivider") }
    }
    var destination = AppDestination.perform
    var showHandsPanel = false
    var showCameraPreview = true
    var showCapture = false
    var showMixer = false
    var showAssignments = false
    var showSave = false
    var showTakeover = false
    var overlay = OverlayVisibility(rawValue: UserDefaults.standard.string(forKey: "rndbuddy.overlay") ?? "") ?? .show {
        didSet { UserDefaults.standard.set(overlay.rawValue, forKey: "rndbuddy.overlay") }
    }
    /// Set by the stage: split layouts keep controls beside the visuals, so overlay visibility does not apply.
    var stageSplit = false
    init() {
        let testing=NSClassFromString("XCTestCase") != nil
        let session = testing ? DeviceSession(transport:FakeMIDITransport(),preferences:nil) : DeviceSession()
        self.session = session
        performance = PerformanceController(session: session)
        pixels = PixelsHost(session: session)
        do { library = try LibraryStore(inMemory:testing) }
        catch { library = nil; startupError = "Library could not open: \(error.localizedDescription)" }
        do {
            let store = try PageStore(inMemory: testing)
            pageStore = store
            performance.pages = try store.load(mappings: library?.mappings.compactMap { try? $0.document() } ?? [])
            if let saved = UserDefaults.standard.string(forKey: "rndbuddy.selectedPage"),
               let index = performance.pages.firstIndex(where: { $0.id.uuidString == saved }) { performance.pageIndex = index }
        } catch { stageError = "Stage pages could not open: \(error.localizedDescription)" }
        hands.onFeatures = { [weak self] values in self?.performance.updateFeatures(values) }
        hands.onContacts = { [weak self] contacts in
            guard let self else { return }
            self.performance.updateSensor(contacts, source: .hands)
        }
        motion.onContacts = { [weak self] contacts in
            guard let self else { return }
            self.performance.updateSensor(contacts, source: .motion)
        }
        if pixels.permission && !testing { pixels.load() }
        if ProcessInfo.processInfo.arguments.contains("--demo") { session.startDemo() }
    }
    func savePages() {
        do { try pageStore?.replace(performance.pages) }
        catch { stageError = error.localizedDescription }
    }
    func presentStage(_ presentation: StagePresentation) {
        performance.cancelTouches()
        stagePresentation = presentation
        if presentation == .hands { Task { await hands.start() } }
    }
    func changeInput(_ method: InputMethod) {
        hands.stop(); motion.stop(); performance.method = method
    }
    func arm(_ value: Bool) {
        performance.armed = value
        if !value { hands.stop(); motion.stop(); return }
        let sources = Set(performance.page.controls.flatMap { $0.bindings.flatMap { $0.sources } })
        let needsHands = sources.contains(.hands) || sources.contains { $0.rawValue.hasPrefix("left") || $0.rawValue.hasPrefix("right") }
        let needsMotion = sources.contains(.motion) || sources.contains(.motionPitch) || sources.contains(.motionRoll)
        if needsHands || performance.method == .hands { Task { await hands.start(); if !performance.armed && stagePresentation != .hands { hands.stop() } } }
        if (needsMotion || performance.method == .motion) && motion.available { motion.start() }
    }
    func background() {
        hands.stop(); motion.stop(); performance.background()
        // User-started audio monitoring intentionally remains active.
    }
}
enum OverlayVisibility: String, CaseIterable, Identifiable {
    case off = "Off", ghost = "Ghost", show = "Show"
    var id: String { rawValue }
}
enum AppDestination: String, CaseIterable, Identifiable {
    case perform = "Perform", library = "Library", settings = "Settings"
    var id: String { rawValue }
    var symbol: String { switch self { case .perform: "slider.horizontal.3"; case .library: "square.stack"; case .settings: "gearshape" } }
}

enum StagePresentation: String { case normal, stage, hands }
