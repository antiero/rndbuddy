import Foundation
import Observation

struct Contact: Identifiable, Equatable, Sendable { let id: String; var x: Double; var y: Double }
@MainActor protocol PerformanceInputSource: AnyObject {
    var onContacts: (([Contact]) -> Void)? { get set }
    func stop()
}

/// Routes every control on the current performance page to the device session.
/// Each control has its own contacts, notes and smoothing history; the most recent
/// control to send a CC owns that CC until another control sends it.
@MainActor @Observable final class PerformanceController {
    let session: DeviceSession
    var editing = false
    var mode = PerformanceMode.modulate { didSet { cancel(); held = false } }
    var method = InputMethod.touch { didSet { cancel(); held = false; armed = false } }
    var pages = PerformancePage.defaults
    var pageIndex = 0 { didSet { if pageIndex != oldValue { cancel() }; if pages.indices.contains(pageIndex) { UserDefaults.standard.set(page.id.uuidString, forKey: "rndbuddy.selectedPage") } } }
    var held = false { didSet { if oldValue && !held { cancel() } } }
    var armed = false { didSet { if !armed { cancel() } } }
    /// Live contacts per control, for drawing.
    private(set) var touches: [UUID: [Contact]] = [:]
    private(set) var faderValues: [UUID: Double] = [:]
    private(set) var pressedKeys: [UUID: Set<Int>] = [:]
    private(set) var toggled: Set<UUID> = []
    private var gestureOrder: [String: Int] = [:]
    private var sequence = 0
    private var sendingSource = InputSource.touch
    private var sensorControls: Set<UUID> = []
    private var contactSources: [UUID: InputSource] = [:]
    private var owners: [String: UUID] = [:]
    private var engine = MappingEngine()
    private var activeIDs: [UUID: Set<String>] = [:]
    private var touchOwns: Set<UUID> = []
    private var lastSensor: [Contact] = []
    private var playVolume: (track: Int, previous: Int?, last: Int, device: Int32?)?
    private var previousDecay = 83
    init(session: DeviceSession) { self.session = session }

    var page: PerformancePage { pages.indices.contains(pageIndex) ? pages[pageIndex] : pages.first ?? .drift() }
    /// The field that hands, motion and the legacy mapping API drive.
    var primaryField: ControlSpec? { page.controls.first { $0.kind == .xy } }
    var contacts: [Contact] { primaryField.flatMap { touches[$0.id] } ?? [] }

    /// Bridges the saved-mapping library and Assignments sheet to the first field.
    var mapping: PerformanceMapping {
        get {
            guard let location = fieldLocation else { return PerformanceMapping() }
            let (p, c) = location
            let field = pages[p].controls[c]
            var mapping = PerformanceMapping(playYAxis: field.playYAxis)
            mapping.x = field.bindings[0].axis; mapping.y = field.bindings[1].axis
            return mapping
        }
        set {
            if mode == .play { cancel() }
            guard let location = fieldLocation else { return }
            let (p, c) = location
            for (index, axis) in [newValue.x, newValue.y].enumerated() {
                let old = pages[p].controls[c].bindings[index]
                pages[p].controls[c].bindings[index] = ControlBinding(axis.target, scope: old.scope, axis: axis, curve: old.curve, sources: old.sources)
            }
            pages[p].controls[c].playYAxis = newValue.playYAxis
            engine.reset()
        }
    }
    var playYAxis: PlayYAxis {
        get { mapping.playYAxis ?? .volume }
        set { mapping.playYAxis = newValue }
    }
    private var fieldLocation: (Int, Int)? {
        let order = [pageIndex] + pages.indices.filter { $0 != pageIndex }
        for p in order where pages.indices.contains(p) {
            if let c = pages[p].controls.firstIndex(where: { $0.kind == .xy && $0.bindings.count == 2 }) { return (p, c) }
        }
        return nil
    }
    private func control(_ id: UUID) -> ControlSpec? { page.controls.first { $0.id == id } }
    private func source(_ control: UUID, _ contact: String) -> String { "\(control.uuidString)-\(contact)" }

    // MARK: Fields

    /// Legacy entry point: touch and sensors on the primary field.
    func update(_ incoming: [Contact], sensor: Bool = false) {
        guard let field = primaryField else { return }
        update(field.id, incoming, sensor: sensor)
    }
    func update(_ id: UUID, _ incoming: [Contact], sensor: Bool = false) {
        guard !editing else { return }
        sendingSource = sensor ? (method == .motion ? .motion : .hands) : .touch
        if incoming.isEmpty { endGesture(id, source: sendingSource) } else { beginGesture(id, source: sendingSource) }
        if sensor {
            lastSensor = incoming
            guard armed, !touchOwns.contains(id) else { return }
        } else if incoming.isEmpty { touchOwns.remove(id) } else { touchOwns.insert(id) }
        if sensor && incoming.isEmpty { apply([], to: id); return }
        guard !held else { return }
        apply(incoming, to: id)
    }
    private func apply(_ incoming: [Contact], to id: UUID) {
        guard let control = control(id) else { return }
        guard !incoming.isEmpty || contactSources[id] == sendingSource else { return }
        let limited = Array(incoming.prefix(4))
        contactSources[id] = limited.isEmpty ? nil : sendingSource
        let sources = limited.map { source(id, "\(sendingSource.rawValue)-\($0.id)") }
        for gone in activeIDs[id, default: []].subtracting(sources) { session.note(source: gone, note: nil, track: session.selectedTrack) }
        activeIDs[id] = sources.isEmpty ? nil : Set(sources)
        touches[id] = limited.isEmpty ? nil : limited
        guard session.canEdit else { return }
        if mode == .modulate {
            guard let contact = limited.first, control.bindings.count == 2 else { return }
            send(control, binding: 0, input: contact.x)
            send(control, binding: 1, input: 1 - contact.y)
        } else {
            let yAxis = control.playYAxis ?? .volume
            if yAxis == .volume { updatePlayVolume(limited) }
            for (contact, source) in zip(limited, sources) {
                let note = RNDProtocolCodec.quantizedNote(x: contact.x, root: session.snapshot.root ?? 0, scale: session.snapshot.scale ?? 0, octave: session.snapshot.octave)
                let velocity = yAxis == .volume ? 127 : Int((1 - contact.y) * 126 + 1).clamped(1...127)
                session.note(source: source, note: note, velocity: velocity, track: session.selectedTrack)
            }
        }
    }
    private func send(_ control: ControlSpec, binding index: Int, input: Double) {
        let binding = control.bindings[index]
        guard !editing, binding.sources.contains(sendingSource) || sendingSource == .touch else { return }
        let gesture = gestureKey(control.id, sendingSource)
        beginGesture(control.id, source: sendingSource)
        let (resolvedCC, resolvedChannel) = binding.control(selectedTrack: session.selectedTrack)
        let target = "\(resolvedCC)/\(resolvedChannel)"
        if let owner = targetGestures[target], owner != gesture,
           let rank = gestureOrder[owner], rank > gestureOrder[gesture, default: 0] { return }
        targetGestures[target] = gesture
        guard FirmwareCapabilities.supports(binding.target, firmware: session.snapshot.firmware),
              let value = engine.value(mapped: binding.mapped(input), key: "\(control.id)#\(index)#\(sendingSource.rawValue)", smoothing: binding.axis.smoothing, deadZone: binding.axis.deadZone)
        else { return }
        let (cc, channel) = binding.control(selectedTrack: session.selectedTrack)
        owners["\(cc)/\(channel)"] = control.id
        session.setControl(cc, value: value, channel: channel)
    }

    // MARK: Faders, toggles, triggers, keys

    /// `nil` ends the gesture. A held fader keeps showing its last value.
    func setFader(_ id: UUID, value: Double?) {
        guard !editing, let control = control(id), control.bindings.count == 1 else { return }
        sendingSource = .touch
        if value == nil { endGesture(id, source: .touch) } else { beginGesture(id, source: .touch) }
        guard let value else { if !held { faderValues[id] = nil }; return }
        guard !held else { return }
        faderValues[id] = value.clamped(0...1)
        guard session.canEdit else { return }
        send(control, binding: 0, input: value)
    }
    /// True when another control sent this control's CC more recently.
    func isOverridden(_ control: ControlSpec) -> Bool {
        control.bindings.contains { binding in
            let (cc, channel) = binding.control(selectedTrack: session.selectedTrack)
            return owners["\(cc)/\(channel)"].map { $0 != control.id } ?? false
        }
    }
    func reported(_ binding: ControlBinding) -> Int? {
        let snapshot = session.snapshot, track = binding.track(selected: session.selectedTrack)
        switch binding.target {
        case .volume: return snapshot.tracks[track].volume
        case .reverb: return snapshot.tracks[track].reverb
        case .masterVolume: return snapshot.masterVolume
        case .masterReverb: return snapshot.masterReverb
        case .tone: return snapshot.reverbParameters[86]
        case .decay: return snapshot.reverbParameters[90]
        }
    }
    func toggle(_ id: UUID) {
        guard !editing, let control = control(id), let binding = control.bindings.first, session.canEdit,
              FirmwareCapabilities.supports(binding.target, firmware: session.snapshot.firmware) else { return }
        let on = !toggled.contains(id)
        if on { toggled.insert(id) } else { toggled.remove(id) }
        let (cc, channel) = binding.control(selectedTrack: session.selectedTrack)
        owners["\(cc)/\(channel)"] = id
        session.setControl(cc, value: Int((binding.mapped(on ? 1 : 0) * 127).rounded()), channel: channel)
    }
    func trigger(_ control: ControlSpec) {
        guard !editing, let action = control.action, FirmwareCapabilities.supports(action, firmware: session.snapshot.firmware) else { return }
        let track = session.selectedTrack
        switch action {
        case .hold: held.toggle()
        case .generate: cancel(); session.generate()
        case .freeze:
            let decay = session.snapshot.reverbParameters[90]
            if decay == 127 { session.setControl(90, value: previousDecay) }
            else { previousDecay = min(126, decay ?? 83); session.setControl(90, value: 127) }
        case .reroll: session.reroll(track)
        case .mute: session.toggleMute(track)
        case .solo: session.toggleSolo(track)
        }
    }
    func isOn(_ control: ControlSpec) -> Bool {
        let track = session.snapshot.tracks[session.selectedTrack]
        switch control.action {
        case .hold: return held
        case .freeze: return session.snapshot.reverbParameters[90] == 127
        case .mute: return track.muted
        case .solo: return track.soloed
        default: return toggled.contains(control.id)
        }
    }
    /// Scale keys only sound in Play mode; the caller asks for takeover first.
    func key(_ id: UUID, degree: Int, down: Bool) {
        let source = source(id, "key\(degree)")
        guard down else {
            pressedKeys[id]?.remove(degree)
            if activeIDs[id]?.remove(source) != nil { session.note(source: source, note: nil, track: session.selectedTrack) }
            return
        }
        guard !editing, mode == .play, session.canEdit else { return }
        pressedKeys[id, default: []].insert(degree)
        let snapshot = session.snapshot
        let note = RNDProtocolCodec.degreeNote(degree, root: snapshot.root ?? 0, scale: snapshot.scale ?? 0, octave: snapshot.octave)
        session.note(source: source, note: note, velocity: 100, track: session.selectedTrack)
        activeIDs[id, default: []].insert(source)
    }

    // MARK: Play volume and lifecycle

    private func updatePlayVolume(_ contacts: [Contact]) {
        guard let height = contacts.map({ 1 - $0.y }).max() else { restorePlayVolume(); return }
        let track = session.selectedTrack
        let value = Int((height.clamped(0...1) * 127).rounded())
        if let current = playVolume, current.track == track, current.last == value { return }
        if let current = playVolume, current.track != track { restorePlayVolume() }
        let previous: Int?
        if let current = playVolume { previous = current.previous }
        else { previous = session.snapshot.tracks[track].volume }
        playVolume = (track, previous, value, session.connectedID)
        session.setControl(7, value: value, channel: track + 2)
    }
    private func restorePlayVolume() {
        guard let current = playVolume else { return }
        playVolume = nil
        // Don't overwrite a later mixer edit or send stale values to a new device.
        guard current.device == session.connectedID, let previous = current.previous,
              session.snapshot.tracks[current.track].volume == current.last else { return }
        session.setControl(7, value: previous, channel: current.track + 2)
    }
    func cancel() {
        for sources in activeIDs.values { for source in sources { session.note(source: source, note: nil, track: session.selectedTrack) } }
        restorePlayVolume()
        activeIDs.removeAll(); touches.removeAll(); faderValues.removeAll(); pressedKeys.removeAll()
        lastSensor = []; engine.reset(); touchOwns.removeAll()
        gestureOrder.removeAll(); targetGestures.removeAll(); owners.removeAll(); sensorControls.removeAll(); contactSources.removeAll()
    }
    private var targetGestures: [String: String] = [:]
    private func gestureKey(_ id: UUID, _ source: InputSource) -> String { "\(id)/\(source.rawValue)" }
    private func beginGesture(_ id: UUID, source: InputSource) {
        let key = gestureKey(id, source)
        if gestureOrder[key] == nil { sequence += 1; gestureOrder[key] = sequence }
    }
    private func endGesture(_ id: UUID, source: InputSource) {
        let key = gestureKey(id, source)
        gestureOrder[key] = nil
        let targets = targetGestures.filter { $0.value == key }.map(\.key)
        for target in targets { targetGestures[target] = nil; owners[target] = nil }
    }
    func cancelTouches() {
        sendingSource = .touch
        for id in Array(touches.keys) where contactSources[id] == .touch { apply([], to: id); endGesture(id, source: .touch) }
        for id in Array(faderValues.keys) { setFader(id, value: nil) }
        for (id, degrees) in pressedKeys { for degree in degrees { key(id, degree: degree, down: false) } }
        touchOwns.removeAll()
    }
    func updateSensor(_ contacts: [Contact], source: InputSource) {
        guard armed, !editing else { return }
        sendingSource = source
        for control in page.controls where control.kind == .xy || control.kind == .fader {
            guard control.bindings.contains(where: { $0.sources.contains(source) }) else { continue }
            if contacts.isEmpty {
                endGesture(control.id, source: source)
                if sensorControls.remove(control.id) != nil { apply([], to: control.id) }
            } else if !touchOwns.contains(control.id) {
                beginGesture(control.id, source: source); sensorControls.insert(control.id)
                if control.kind == .xy { apply(contacts, to: control.id) }
                else if let first = contacts.first { send(control, binding: 0, input: 1 - first.y) }
            }
        }
        if source == .motion && contacts.isEmpty { updateFeatures([:], motion: true) }
        if source == .motion, let contact = contacts.first {
            updateFeatures([.motionRoll: contact.x, .motionPitch: 1 - contact.y], motion: true)
        }
    }
    func updateFeatures(_ values: [InputSource: Double], motion: Bool = false) {
        guard armed, !editing else { return }
        let features = InputSource.allCases.filter { ![.touch, .hands, .motion, .keys].contains($0) }
        for control in page.controls {
            for (index, binding) in control.bindings.enumerated() {
                for feature in features where binding.sources.contains(feature) {
                    if let value = values[feature] {
                        sendingSource = feature; beginGesture(control.id, source: feature)
                        send(control, binding: index, input: value)
                    } else if feature.rawValue.hasPrefix("motion") == motion {
                        endGesture(control.id, source: feature)
                    }
                }
            }
        }
    }
    func background() { armed = false; held = false; cancel(); session.releaseAll() }
}
