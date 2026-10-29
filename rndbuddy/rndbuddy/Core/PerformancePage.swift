import Foundation

// Stage redesign, phase 1: artist-arranged performance pages. See docs/StageRedesign.md.
// Pure data and capability rules only; routing and UI arrive in later phases.

enum ControlKind: String, Codable, CaseIterable, Sendable { case xy, fader, trigger, toggle, keys, tracks, patchBar, camera }
enum TrackScope: Codable, Hashable, Sendable { case selected, fixed(Int) }
enum ResponseCurve: String, Codable, CaseIterable, Sendable {
    case linear, soft, exponential
    /// Monotonic on 0...1 with fixed end points, so ranges and inversion keep their meaning.
    func apply(_ value: Double) -> Double {
        let x = value.clamped(0...1)
        switch self {
        case .linear: return x
        case .soft: return x * x * (3 - 2 * x)
        case .exponential: return x * x
        }
    }
}
enum TriggerAction: String, Codable, CaseIterable, Sendable { case generate, hold, freeze, reroll, mute, solo }
/// Inputs that may drive a binding. Hands and motion supply the binding's own axis; finer hand features come later.
enum InputSource: String, Codable, CaseIterable, Sendable { case touch, hands, motion, keys, rightPalmX, rightPalmY, leftPalmX, leftPalmY, rightHeight, leftHeight, rightPinch, leftPinch, motionPitch, motionRoll }

struct ControlBinding: Codable, Equatable, Sendable {
    var target: MappingTarget
    var scope: TrackScope = .selected
    var axis: AxisMapping
    var curve: ResponseCurve = .linear
    var sources: Set<InputSource> = [.touch]
    init(_ target: MappingTarget, scope: TrackScope = .selected, axis: AxisMapping? = nil, curve: ResponseCurve = .linear, sources: Set<InputSource> = [.touch]) {
        self.target = target; self.scope = scope; self.axis = axis ?? AxisMapping(target: target); self.curve = curve; self.sources = sources
        self.axis.target = target
    }
    /// Invert, then curve, then range: 0...1 in, 0...1 out.
    func mapped(_ input: Double) -> Double {
        let value = axis.inverted ? 1 - input.clamped(0...1) : input.clamped(0...1)
        return axis.minimum + curve.apply(value) * (axis.maximum - axis.minimum)
    }
    /// Master targets ignore scope; track targets resolve against the selected track unless fixed.
    func track(selected: Int) -> Int {
        if case .fixed(let track) = scope { return track.clamped(0...3) }
        return selected.clamped(0...3)
    }
    func control(selectedTrack: Int) -> (cc: Int, channel: Int) {
        target.control(track: track(selected: selectedTrack))
    }
}

struct ControlSpec: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var kind: ControlKind
    var title: String
    var bindings: [ControlBinding] = []
    var action: TriggerAction?
    var playYAxis: PlayYAxis?
    init(id: UUID = UUID(), kind: ControlKind, title: String, bindings: [ControlBinding] = [], action: TriggerAction? = nil, playYAxis: PlayYAxis? = nil) {
        self.id = id; self.kind = kind; self.title = title; self.bindings = bindings; self.action = action; self.playYAxis = playYAxis
    }
    /// Bindings each kind consumes: xy uses x then y, fader one, keys none (notes plus playYAxis).
    var expectedBindings: ClosedRange<Int> {
        switch kind {
        case .xy: 2...2
        case .fader: 1...1
        case .toggle: 0...1
        case .trigger, .keys, .tracks, .patchBar, .camera: 0...0
        }
    }
}

/// Grid units on a layout class's grid. Stored per layout class so each device keeps its own arrangement.
struct Placement: Codable, Equatable, Sendable {
    var controlID: UUID
    var column: Int
    var row: Int
    var width: Int
    var height: Int
    func overlaps(_ other: Placement) -> Bool {
        column < other.column + other.width && other.column < column + width &&
        row < other.row + other.height && other.row < row + height
    }
}

enum LayoutClass: String, Codable, CaseIterable, Sendable, CodingKeyRepresentable {
    case mac, padLandscape, padPortrait, phonePortrait, phoneLandscape, foldOpen, foldTabletop
    /// Grid for the performance layer (not the whole screen); one unit is roughly a 44 pt touch target.
    var grid: (columns: Int, rows: Int) {
        switch self {
        case .mac: (24, 14)
        case .padLandscape: (20, 13)
        case .padPortrait: (14, 10)
        case .phonePortrait: (8, 10)
        case .phoneLandscape: (16, 6)
        case .foldOpen: (10, 12)
        case .foldTabletop: (20, 6)
        }
    }
}

enum PageError: LocalizedError, Equatable {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let reason): "This layout could not be saved: \(reason)." }
    }
}

struct PerformancePage: Codable, Identifiable, Equatable, Sendable {
    static let maxControls = 64
    var schemaVersion = 1
    let id: UUID
    var name: String
    var controls: [ControlSpec]
    var placements: [LayoutClass: [Placement]] = [:]
    init(id: UUID = UUID(), name: String, controls: [ControlSpec], placements: [LayoutClass: [Placement]] = [:]) {
        self.id = id; self.name = name; self.controls = controls; self.placements = placements
    }
    /// Rejects data the router could not use safely; call on import and before saving.
    func validate() throws {
        guard schemaVersion == 1 else { throw PageError.invalid("Unsupported page version") }
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty, name.count <= 80 else { throw PageError.invalid("Page name") }
        guard controls.count <= Self.maxControls, Set(controls.map(\.id)).count == controls.count else { throw PageError.invalid("Controls") }
        for control in controls {
            guard control.expectedBindings.contains(control.bindings.count) else { throw PageError.invalid("Bindings for \(control.title)") }
            guard (control.kind == .trigger) == (control.action != nil) else { throw PageError.invalid("Action for \(control.title)") }
            for binding in control.bindings {
                if case .fixed(let track) = binding.scope, !(0...3).contains(track) { throw PageError.invalid("Track") }
                let axis = binding.axis
                guard (0...1).contains(axis.minimum), (0...1).contains(axis.maximum), (0...0.95).contains(axis.smoothing), (0...0.1).contains(axis.deadZone) else {
                    throw PageError.invalid("Range for \(control.title)")
                }
            }
        }
        let ids = Set(controls.map(\.id))
        for (layout, list) in placements {
            guard Set(list.map(\.controlID)).count == list.count else { throw PageError.invalid("Duplicate placement") }
            for (index, placement) in list.enumerated() {
                guard !list.dropFirst(index + 1).contains(where: { placement.overlaps($0) }) else { throw PageError.invalid("Overlapping placement") }
            }
            let grid = layout.grid
            for placement in list where !ids.contains(placement.controlID) || placement.width < 1 || placement.height < 1
                || placement.column < 0 || placement.row < 0 || placement.column + placement.width > grid.columns || placement.row + placement.height > grid.rows {
                throw PageError.invalid("Placement")
            }
        }
    }
}

extension PerformancePage {
    /// Matches today's Perform screen so existing users lose nothing.
    static func drift(_ legacy: PerformanceMapping = PerformanceMapping()) -> PerformancePage {
        PerformancePage(name: "Drift", controls: [
            ControlSpec(kind: .xy, title: "Field", bindings: [binding(legacy.x), binding(legacy.y)], playYAxis: legacy.playYAxis ?? .volume),
            ControlSpec(kind: .fader, title: "Vol", bindings: [ControlBinding(.masterVolume)]),
            ControlSpec(kind: .fader, title: "Verb", bindings: [ControlBinding(.masterReverb)]),
            ControlSpec(kind: .trigger, title: "Hold", action: .hold),
            ControlSpec(kind: .trigger, title: "Freeze", action: .freeze),
            ControlSpec(kind: .trigger, title: "Reroll", action: .reroll),
            ControlSpec(kind: .trigger, title: "Mute", action: .mute),
            ControlSpec(kind: .tracks, title: "Tracks"),
            ControlSpec(kind: .patchBar, title: "Patch"),
        ])
    }
    static func keys(playYAxis: PlayYAxis = .volume) -> PerformancePage {
        PerformancePage(name: "Keys", controls: [
            ControlSpec(kind: .keys, title: "Keys", playYAxis: playYAxis),
            ControlSpec(kind: .tracks, title: "Tracks"),
            ControlSpec(kind: .patchBar, title: "Patch"),
        ])
    }
    /// Per-track volume faders plus the track actions from the mixer.
    static func swell() -> PerformancePage {
        PerformancePage(name: "Swell", controls: (0..<4).map { track in
            ControlSpec(kind: .fader, title: "T\(track + 1)", bindings: [ControlBinding(.volume, scope: .fixed(track))])
        } + [
            ControlSpec(kind: .fader, title: "Verb", bindings: [ControlBinding(.reverb)]),
            ControlSpec(kind: .trigger, title: "Mute", action: .mute),
            ControlSpec(kind: .trigger, title: "Freeze", action: .freeze),
            ControlSpec(kind: .trigger, title: "Reroll", action: .reroll),
            ControlSpec(kind: .tracks, title: "Tracks"),
            ControlSpec(kind: .patchBar, title: "Patch"),
        ])
    }
    static var defaults: [PerformancePage] { [drift().withStagePlacements(), swell().withStagePlacements(), keys().withStagePlacements()] }
    /// One page per saved mapping when migrating the library.
    init(legacy mapping: PerformanceMapping, name: String) {
        var safe = mapping
        for path in [\PerformanceMapping.x, \PerformanceMapping.y] {
            safe[keyPath: path].minimum = safe[keyPath: path].minimum.clamped(0...1)
            safe[keyPath: path].maximum = safe[keyPath: path].maximum.clamped(0...1)
            safe[keyPath: path].smoothing = safe[keyPath: path].smoothing.clamped(0...0.95)
            safe[keyPath: path].deadZone = safe[keyPath: path].deadZone.clamped(0...0.1)
        }
        self = .drift(safe)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = trimmed.isEmpty ? "Imported mapping" : String(trimmed.prefix(80))
    }
    private static func binding(_ axis: AxisMapping) -> ControlBinding { ControlBinding(axis.target, axis: axis, sources: [.touch, .hands, .motion]) }
}

/// Single source of truth for firmware-gated controls; the router, inspector and unavailable state all ask here.
enum FirmwareCapabilities {
    static func supports(_ target: MappingTarget, firmware: FirmwareProfile) -> Bool {
        guard firmware.supportsEditing else { return false }
        return !target.deep || firmware.supportsDeepReverb
    }
    static func supports(_ action: TriggerAction, firmware: FirmwareProfile) -> Bool {
        switch action {
        case .hold: true
        case .generate, .mute, .solo: firmware.supportsEditing
        case .freeze: firmware.supportsDeepReverb
        case .reroll: firmware == .jg023
        }
    }
    static func supports(_ control: ControlSpec, firmware: FirmwareProfile) -> Bool {
        if let action = control.action { return supports(action, firmware: firmware) }
        return control.bindings.allSatisfy { supports($0.target, firmware: firmware) }
    }
    /// Short reason for the unavailable state; nil when supported.
    static func reason(_ control: ControlSpec, firmware: FirmwareProfile) -> String? {
        if supports(control, firmware: firmware) { return nil }
        return firmware.supportsEditing ? "Needs JG firmware" : "Firmware not detected"
    }
}
