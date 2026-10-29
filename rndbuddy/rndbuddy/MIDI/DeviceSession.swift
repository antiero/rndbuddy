// JG protocol and recall behaviour adapts jgharding/JG-RND (MIT, copyright 2026 jgharding).
// Full upstream licence: docs/ThirdPartyNotices.md in the app project.
import Foundation
import Observation
import CoreAudio

@MainActor @Observable final class DeviceSession {
    let transport: any MIDITransport
    private(set) var snapshot = PatchSnapshot()
    private(set) var reported = PatchSnapshot()
    private(set) var connectedID: Int32?
    private(set) var recent: [PatchSnapshot] = []
    private(set) var activity = [Double](repeating: 0, count: 4)
    private(set) var demo = false
    private(set) var recalling = false
    private(set) var clockSource = "RND"
    private(set) var externalClockAt: Date?
    var error: String?
    var selectedTrack = 0
    var onEvent: ((MIDIEvent) -> Void)?
    var onNativeEvent: ((MIDIEvent) -> Void)?
    var onConnectionChanged: (() -> Void)?
    private var recallTask: Task<Void, Never>?
    private var demoTask: Task<Void, Never>?
    private var queryTask: Task<Void, Never>?
    private var notes: [String: (Int, Int)] = [:]
    private let preferences:UserDefaults?
    private var wantsConnection=true
    var connected: Bool { connectedID != nil }
    var canEdit: Bool { demo || (connected && snapshot.firmware.supportsEditing) }
    var displayName: String { demo ? "Demo" : transport.endpoints.first { $0.id == connectedID }?.name ?? "Connect RND" }

    init(transport: any MIDITransport = CoreMIDITransport(),preferences:UserDefaults? = .standard) {
        self.transport = transport; self.preferences=preferences
        transport.onReceive = { [weak self] event in self?.receive(event) }
        transport.onEndpointsChanged = { [weak self] in self?.endpointsChanged() }
        endpointsChanged()
    }
    func endpointsChanged() {
        if let id = connectedID, !transport.endpoints.contains(where: { $0.id == id }) { connect(nil,keepAutoReconnect:true) }
        if !connected && !demo && wantsConnection {
            let stored = preferences?.object(forKey: "rndbuddy.endpoint") as? Int
            let preferred = transport.endpoints.first { Int($0.id) == stored }
            let matches = transport.endpoints.filter { $0.name.localizedCaseInsensitiveContains("rnd") }
            if let endpoint = preferred ?? (matches.count == 1 ? matches.first : nil) { connect(endpoint.id) }
        }
        onConnectionChanged?()
    }
    func connect(_ id: Int32?,keepAutoReconnect:Bool=false) {
        if !keepAutoReconnect { wantsConnection=id != nil }
        releaseAll(); stopClock(); queryTask?.cancel(); recallTask?.cancel()
        if recalling && snapshot.firmware == .jg023 { send(RNDProtocolCodec.message(0x1B,[0])) }
        recalling = false
        demoTask?.cancel(); demo = false
        connectedID = id
        snapshot = PatchSnapshot(); reported = PatchSnapshot()
        transport.select(transport.endpoints.first { $0.id == id })
        if let id {
            preferences?.set(Int(id), forKey: "rndbuddy.endpoint")
            // JG's version query is distinct. Official identification is requested
            // only after the user selects Official, avoiding its JG engine opcode clash.
            send(RNDProtocolCodec.message(0x7E))
            send(RNDProtocolCodec.message(0x18))
        }
        onConnectionChanged?()
    }
    func selectFirmware(_ profile: FirmwareProfile) {
        guard connected else { return }
        snapshot.firmware = profile; reported.firmware = profile
        if profile == .official14 { send(RNDProtocolCodec.message(0x19)) }
        if profile == .unknown { send(RNDProtocolCodec.message(0x7E)) }
        requestSnapshot()
    }
    func requestSnapshot() { if connected { send(RNDProtocolCodec.message(0x18)) } }
    func startDemo() {
        connect(nil); demo = true
        snapshot = PatchSnapshot(seed: 0xA17C9203, firmware: .jg023, tempo: 108, root: 0, scale: 6, type: 0, masterVolume: 100, masterReverb: 64)
        for track in 0..<4 { snapshot.tracks[track].engine = ["FM", "Plucked String", "Acid (303)", "Noise"][track]; snapshot.tracks[track].active = true; snapshot.tracks[track].volume = 90; snapshot.tracks[track].reverb = 64 }
        reported = snapshot
        demoTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60.0 / Double(self?.snapshot.tempo ?? 108) / 24))
                guard !Task.isCancelled, let self else { return }
                tick += 1
                self.onEvent?(MIDIEvent(bytes:[0xF8],hostTime:mach_absolute_time()))
                if tick % 6 == 0 || tick % 6 == 3 {
                    let step = tick / 6, track = step % 4
                    let on = tick % 6 == 0
                    self.activity[track] = on ? 0.8 : 0.1
                    self.onEvent?(MIDIEvent(bytes:[UInt8((on ? 0x90 : 0x80)+track), UInt8(48+step%24), on ? 90 : 0], hostTime:mach_absolute_time()))
                }
            }
        }
        onConnectionChanged?()
    }
    func send(_ data: [UInt8], at time: UInt64 = 0, echo: Bool = true) {
        if echo { onNativeEvent?(MIDIEvent(bytes:data,hostTime:time == 0 ? mach_absolute_time() : time)) }
        guard !demo, connected else { return }
        do { try transport.send(data, at: time) } catch { self.error = error.localizedDescription }
    }
    func receive(_ event: MIDIEvent) {
        let bytes = event.bytes
        guard let status = bytes.first else { return }
        onEvent?(event)
        if status == 0xF8 {
            externalClockAt = .now
            if clockSource == "App" { stopClock() }
        }
        if bytes.count == 3 && status & 0xF0 == 0x90 && bytes[2] > 0 {
            let track = Int(status & 0x0F)
            if track < 4 { activity[track] = Double(bytes[2]) / 127 }
        }
        guard bytes.starts(with: RNDProtocolCodec.header), bytes.count >= 6, bytes.last == 0xF7 else { return }
        let command = bytes[4], payload = Array(bytes.dropFirst(5).dropLast())
        switch command {
        case 0x7F where payload.count == 4:
            if payload[0] == 1 && payload[1] == 3 && Int(payload[2]) + (Int(payload[3]) << 7) == 23 {
                snapshot.firmware = .jg023; reported.firmware = .jg023
                send(RNDProtocolCodec.message(0x1C)) // JG storage query; never sent to official firmware.
            }
        case 0x23 where payload.count == 2 && snapshot.firmware != .jg023:
            if payload == [1,4] { snapshot.firmware = .official14; reported.firmware = .official14 }
        case 0x10 where payload.count >= 5:
            let seed = RNDProtocolCodec.unpack(payload[0..<5])
            if snapshot.seed != seed && !recalling {
                if snapshot.seed != nil { recent.insert(snapshot, at: 0); recent = Array(recent.prefix(32)) }
                let firmware = snapshot.firmware
                snapshot = PatchSnapshot(seed: seed, firmware: firmware)
                reported = snapshot
            } else { snapshot.seed = seed; reported.seed = seed }
        case 0x21 where payload.count >= 5:
            let bpm = Int(payload[1]) | Int(payload[2]) << 7
            guard payload[0] < 3, payload[3] < 12, payload[4] < 20, (20...400).contains(bpm) else { return }
            reported.type = Int(payload[0]); reported.tempo = bpm; reported.root = Int(payload[3]); reported.scale = Int(payload[4])
            if !recalling { snapshot.type = reported.type; snapshot.tempo = bpm; snapshot.root = reported.root; snapshot.scale = reported.scale }
        case 0x20:
            if !recalling { for index in 0..<4 { snapshot.tracks[index].active = false } }
        case 0x22 where payload.count >= 4:
            let track = Int(payload[0]); guard track < 4 else { return }
            let name = String(bytes: payload.dropFirst(3).prefix { $0 != 0 }, encoding: .ascii)
            reported.tracks[track].engine = name; reported.tracks[track].active = true
            if !recalling { snapshot.tracks[track].engine = name; snapshot.tracks[track].active = true }
        case 0x23 where payload.count == 6 && snapshot.firmware == .jg023:
            let track = Int(payload[0]); guard track < 4 else { return }
            let seed = RNDProtocolCodec.unpack(payload[1..<6]); snapshot.tracks[track].rerollSeed = seed; reported.tracks[track].rerollSeed = seed
        case 0x24 where payload.count >= 13 && snapshot.firmware == .jg023:
            let mask = Int(payload[0])
            if (1...7).contains(mask) { reported.generationMask = mask; if !recalling { snapshot.generationMask = mask } }
        case 0x26 where payload.count >= 5 && snapshot.firmware == .official14:
            let locks = DeviceLocks.decode(RNDProtocolCodec.unpack(payload[0..<5]))
            reported.locks = locks
            if !recalling { snapshot.locks = locks; if let locks { snapshot.octave = 4+locks.rootOctave } }
        case 0x28 where payload.count >= 9 && snapshot.firmware == .official14:
            for track in 0..<4 {
                reported.tracks[track].volume = Int(payload[track]); reported.tracks[track].reverb = Int(payload[track + 4])
                if !recalling { snapshot.tracks[track].volume = reported.tracks[track].volume; snapshot.tracks[track].reverb = reported.tracks[track].reverb }
            }
        case 0x25 where payload.count >= 1 && snapshot.firmware == .official14:
            if payload[0] == 1 || payload[0] == 2 { externalClockAt = .now; stopClock(); clockSource = "External" }
            else if clockSource != "App" { clockSource = "RND" }
        default: break
        }
    }
    func generate() {
        guard canEdit, !recalling else { return }
        releaseAll()
        if demo {
            recent.insert(snapshot, at: 0); recent = Array(recent.prefix(32))
            snapshot.seed = (snapshot.seed ?? 1) &* 1_664_525 &+ 1_013_904_223
        } else { send(RNDProtocolCodec.message(0x10)); requestSnapshot() }
    }
    func setControl(_ cc: Int, value: Int, channel: Int = 1) {
        guard canEdit, !recalling else { return }
        let value = value.clamped(0...127)
        if cc == 7, (2...5).contains(channel), snapshot.firmware == .official14 {
            let track = snapshot.tracks[channel-2]
            let anySolo = snapshot.tracks.contains { $0.soloed }
            send(RNDProtocolCodec.cc(cc, track.muted || (anySolo && !track.soloed) ? 0 : value, channel:channel))
        } else { send(RNDProtocolCodec.cc(cc, value, channel: channel)) }
        if channel == 1 {
            if cc == 7 { snapshot.masterVolume = value }
            if cc == 91 { snapshot.masterReverb = value }
            if (85...90).contains(cc) && snapshot.firmware == .jg023 { snapshot.reverbParameters[cc] = value }
        } else if (2...5).contains(channel) {
            if cc == 7 { snapshot.tracks[channel - 2].volume = value }
            if cc == 91 { snapshot.tracks[channel - 2].reverb = value }
        }
    }
    func setScale(_ scale: Int) {
        guard canEdit, !recalling else { return }; releaseAll()
        send(RNDProtocolCodec.cc(9, RNDProtocolCodec.scaleCC(scale, firmware: snapshot.firmware)))
        snapshot.scale = scale
        if snapshot.firmware == .official14 { snapshot.locks = snapshot.locks ?? DeviceLocks(); snapshot.locks?.scale = scale }
    }
    func setRoot(_ root: Int) {
        guard canEdit, !recalling else { return }; releaseAll()
        let note = ((snapshot.octave + 1) * 12 + root).clamped(0...127)
        send([0x90, UInt8(note), 80]); send([0x80, UInt8(note), 0]); snapshot.root = root
        if snapshot.firmware == .official14 { snapshot.locks = snapshot.locks ?? DeviceLocks(); snapshot.locks?.root = root; snapshot.locks?.rootOctave = snapshot.octave-4 }
    }
    func setType(_ type: Int) {
        guard canEdit, !recalling else { return }
        send(RNDProtocolCodec.cc(14, RNDProtocolCodec.typeCC(type, firmware: snapshot.firmware))); snapshot.type = type
        if snapshot.firmware == .official14 { snapshot.locks = snapshot.locks ?? DeviceLocks(); snapshot.locks?.type = type }
        else if snapshot.firmware == .jg023 { snapshot.generationMask = 1 << type }
    }
    func setGenerationMask(_ mask: Int) {
        guard canEdit, !recalling, snapshot.firmware == .jg023, (1...7).contains(mask) else { return }
        send(RNDProtocolCodec.cc(14,mask)); snapshot.generationMask = mask
    }
    func setTrackCount(_ count: Int?) {
        guard canEdit, !recalling, snapshot.firmware == .official14 else { return }
        send(RNDProtocolCodec.message(0x1F,[UInt8(count?.clamped(1...4) ?? 127)]))
        snapshot.locks = snapshot.locks ?? DeviceLocks(); snapshot.locks?.tracks = count
    }
    func setTempo(_ bpm: Int) {
        guard canEdit, !recalling, clockSource != "External", let bytes = RNDProtocolCodec.tempo(bpm, firmware: snapshot.firmware, snapshot: snapshot) else { return }
        send(bytes); snapshot.tempo = bpm
        if clockSource == "App" && !demo { do { try transport.startClock(bpm:bpm) } catch { self.error = error.localizedDescription; stopClock() } }
    }
    func setEngine(_ index: Int, track: Int) {
        guard canEdit, !recalling, let bytes = RNDProtocolCodec.engine(index, track: track, firmware: snapshot.firmware) else { return }
        send(bytes); snapshot.tracks[track].engineOverride = index; snapshot.tracks[track].engine = RNDProtocolCodec.engines[index]
        if snapshot.firmware == .official14 { snapshot.locks = snapshot.locks ?? DeviceLocks(); snapshot.locks?.engines[track] = index }
    }
    func reroll(_ track: Int) {
        guard canEdit, !recalling, snapshot.firmware == .jg023 else { return }
        send(RNDProtocolCodec.message(0x12, [UInt8(track)]))
    }
    func toggleMute(_ track: Int) {
        guard canEdit, !recalling else { return }
        snapshot.tracks[track].muted.toggle()
        if snapshot.firmware == .jg023 { send(RNDProtocolCodec.message(0x16, [UInt8(track), snapshot.tracks[track].muted ? 1 : 0])) }
        else { send(RNDProtocolCodec.cc(7, snapshot.tracks[track].muted ? 0 : snapshot.tracks[track].volume ?? 100, channel: track + 2)) }
    }
    func toggleSolo(_ track: Int) {
        guard canEdit, !recalling else { return }
        snapshot.tracks[track].soloed.toggle()
        if snapshot.firmware == .jg023 { send(RNDProtocolCodec.message(0x17, [UInt8(track), snapshot.tracks[track].soloed ? 1 : 0])) }
        else {
            let anySolo = snapshot.tracks.contains { $0.soloed }
            for item in snapshot.tracks { send(RNDProtocolCodec.cc(7, item.muted || (anySolo && !item.soloed) ? 0 : item.volume ?? 100, channel: item.id + 2)) }
        }
    }
    func note(source: String, note: Int?, velocity: Int = 90, track: Int) {
        guard !recalling else { return }
        let channel = (track + 1).clamped(0...15) // native track takeover is channel 2...5
        let note = note?.clamped(0...127)
        if let old = notes[source] {
            if note == old.1 && channel == old.0 { return }
            // Shared pitches remain held until the last owner releases.
            notes[source] = nil
            if !notes.values.contains(where: { $0 == old }) { send([UInt8(0x80 | old.0), UInt8(old.1), 0]) }
        }
        guard canEdit, let note else { return }
        let alreadyHeld = notes.values.contains { $0 == (channel, note) }
        notes[source] = (channel, note)
        if !alreadyHeld { send([UInt8(0x90 | channel), UInt8(note.clamped(0...127)), UInt8(velocity.clamped(1...127))]) }
    }
    func releaseNotes(prefix: String) {
        for source in Array(notes.keys) where source.hasPrefix(prefix) { note(source:source,note:nil,track:0) }
    }
    private func scheduleSnapshotRead() {
        queryTask?.cancel()
        let id = connectedID
        queryTask = Task { [weak self] in
            try? await Task.sleep(for:.milliseconds(150))
            guard !Task.isCancelled, let self, self.connectedID == id else { return }
            self.requestSnapshot()
        }
    }
    func receiveWeb(_ bytes: [UInt8]) {
        if bytes.count == 3 && (bytes[0] & 0xF0 == 0x90 || bytes[0] & 0xF0 == 0x80) {
            let channel = Int(bytes[0] & 15)
            let source = "pixels-\(channel)-\(bytes[1])"
            let on = bytes[0] & 0xF0 == 0x90 && bytes[2] > 0
            note(source:source,note:on ? Int(bytes[1]) : nil,velocity:Int(bytes[2]),track:channel-1)
        } else { send(bytes,echo:false) }
        if let status = bytes.first, status < 0xF8 { scheduleSnapshotRead() }
    }
    func releaseAll() {
        let owned = notes; notes.removeAll()
        for (_, pair) in owned { send([UInt8(0x80 | pair.0), UInt8(pair.1), 0]) }
    }
    func recall(_ patch: PatchSnapshot) {
        guard canEdit, let seed = patch.seed, !recalling else { return }
        releaseAll(); let profile = snapshot.firmware
        recalling = true
        recallTask = Task { [weak self] in
            guard let self else { return }
            defer { self.recalling = false }
            if profile == .jg023 { self.send(RNDProtocolCodec.message(0x1B, [1])) }
            if profile == .official14 {
                self.send(RNDProtocolCodec.message(0x1C))
                for message in patch.locks?.messages() ?? [] { self.send(message) }
            }
            self.send(RNDProtocolCodec.message(0x10, RNDProtocolCodec.packed(seed)))
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            self.snapshot = patch; self.snapshot.firmware = profile
            let s = self.snapshot
            if let scale = s.scale { self.send(RNDProtocolCodec.cc(9, RNDProtocolCodec.scaleCC(scale, firmware: profile))) }
            if profile == .jg023, let mask = s.generationMask { self.send(RNDProtocolCodec.cc(14,mask)) }
            else if let type = s.type { self.send(RNDProtocolCodec.cc(14, RNDProtocolCodec.typeCC(type, firmware: profile))) }
            if let bpm = s.tempo, let bytes = RNDProtocolCodec.tempo(bpm, firmware: profile, snapshot: s) { self.send(bytes) }
            if let root = s.root { let note = UInt8(((s.octave + 1) * 12 + root).clamped(0...127)); self.send([0x90,note,80]); self.send([0x80,note,0]) }
            for (cc, value) in [(7,s.masterVolume),(91,s.masterReverb)] { if let value { self.send(RNDProtocolCodec.cc(cc,value)) } }
            for track in s.tracks {
                if let engine = track.engineOverride, let bytes = RNDProtocolCodec.engine(engine, track: track.id, firmware: profile) { self.send(bytes) }
                if profile == .jg023, let reroll = track.rerollSeed { self.send(RNDProtocolCodec.message(0x1A, [UInt8(track.id)] + RNDProtocolCodec.packed(reroll))) }
                if let volume = track.volume { self.send(RNDProtocolCodec.cc(7, volume, channel: track.id + 2)) }
                if let reverb = track.reverb { self.send(RNDProtocolCodec.cc(91, reverb, channel: track.id + 2)) }
                if profile == .jg023 {
                    self.send(RNDProtocolCodec.message(0x16,[UInt8(track.id), track.muted ? 1 : 0]))
                    self.send(RNDProtocolCodec.message(0x17,[UInt8(track.id), track.soloed ? 1 : 0]))
                }
            }
            if profile == .official14 {
                let anySolo = s.tracks.contains { $0.soloed }
                for track in s.tracks where track.muted || (anySolo && !track.soloed) { self.send(RNDProtocolCodec.cc(7,0,channel:track.id+2)) }
            }
            if profile == .jg023 {
                for (cc,value) in s.reverbParameters.sorted(by: { $0.key < $1.key }) { self.send(RNDProtocolCodec.cc(cc,value)) }
                self.send(RNDProtocolCodec.message(0x1B,[0]))
            }
            self.requestSnapshot()
        }
    }
    func startClock() {
        guard canEdit, clockSource != "External", externalClockAt.map({ Date().timeIntervalSince($0) > 2 }) ?? true else { error = "RND is following an external clock."; return }
        stopClock(); clockSource = "App"; send([0xFA])
        if !demo {
            do { try transport.startClock(bpm:snapshot.tempo ?? 120) }
            catch { self.error = error.localizedDescription; stopClock() }
        }
    }
    func stopClock() { transport.stopClock(); clockSource = "RND" }
}
