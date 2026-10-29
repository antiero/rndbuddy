import Foundation
import Observation

struct Contact: Identifiable, Equatable, Sendable { let id: String; var x: Double; var y: Double }
@MainActor protocol PerformanceInputSource: AnyObject {
    var onContacts: (([Contact]) -> Void)? { get set }
    func stop()
}

@MainActor @Observable final class PerformanceController {
    let session: DeviceSession
    var mode = PerformanceMode.modulate { didSet { cancel(); held = false } }
    var method = InputMethod.touch { didSet { cancel(); held = false; armed = false } }
    var mapping = PerformanceMapping() {
        willSet { if mode == .play { cancel() } }
        didSet { engine.reset() }
    }
    var playYAxis: PlayYAxis {
        get { mapping.playYAxis ?? .volume }
        set { mapping.playYAxis = newValue }
    }
    private var playVolume: (track: Int, previous: Int?, last: Int, device: Int32?)?
    var held = false { didSet { if oldValue && !held { cancel() } } }
    var armed = false { didSet { if !armed { cancel() } } }
    private(set) var contacts: [Contact] = []
    private var engine = MappingEngine()
    private var activeIDs: Set<String> = []
    private var touchOwns = false
    private var notes: [String: Int] = [:]
    private var lastSensor: [Contact] = []
    init(session: DeviceSession) { self.session = session }
    func update(_ incoming: [Contact], sensor: Bool = false) {
        if sensor {
            lastSensor = incoming
            guard armed, !touchOwns else { return }
        } else { touchOwns = !incoming.isEmpty }
        if sensor && incoming.isEmpty { apply([]); return }
        guard !held else { return }
        apply(incoming)
        if !sensor && incoming.isEmpty && armed { apply(lastSensor) }
    }
    private func apply(_ incoming: [Contact]) {
        let limited = Array(incoming.prefix(4)); let ids = Set(limited.map(\.id))
        for id in activeIDs.subtracting(ids) { session.note(source: id, note: nil, track: session.selectedTrack); notes[id] = nil }
        activeIDs = ids; contacts = limited
        guard session.canEdit else { return }
        if mode == .modulate {
            guard let contact = limited.first else { return }
            for (input, axis) in [(contact.x, mapping.x), (1 - contact.y, mapping.y)] {
                guard !axis.target.deep || session.snapshot.firmware == .jg023 else { continue }
                if let value = engine.value(input, axis: axis) {
                    let (cc, channel) = axis.target.control(track: session.selectedTrack)
                    session.setControl(cc, value: value, channel: channel)
                }
            }
        } else {
            if playYAxis == .volume { updatePlayVolume(limited) }
            for contact in limited {
                let note = RNDProtocolCodec.quantizedNote(x: contact.x, root: session.snapshot.root ?? 0, scale: session.snapshot.scale ?? 0, octave: session.snapshot.octave)
                let velocity = playYAxis == .volume ? 127 : Int((1 - contact.y) * 126 + 1).clamped(1...127)
                session.note(source: contact.id, note: note, velocity: velocity, track: session.selectedTrack)
                notes[contact.id] = note
            }
        }
    }
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
        for id in activeIDs { session.note(source: id, note: nil, track: session.selectedTrack) }
        restorePlayVolume()
        activeIDs.removeAll(); notes.removeAll(); contacts = []; lastSensor = []
        engine.reset(); touchOwns = false
    }
    func background() { armed = false; held = false; cancel(); session.releaseAll() }
}
