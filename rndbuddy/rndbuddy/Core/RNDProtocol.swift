import Foundation

// JG messages adapted from jgharding/JG-RND (MIT, copyright 2026 jgharding).
// Official messages observed in the public RND pixels MIDI client, October 2026.
enum FirmwareProfile: String, Codable, CaseIterable, Sendable, Identifiable {
    case unknown, official14, jg023
    var id: String { rawValue }
    var title: String {
        switch self { case .unknown: "Detect automatically"; case .official14: "Official 1.4"; case .jg023: "JGpatch-023" }
    }
    var supportsEditing: Bool { self != .unknown }
    var supportsDeepReverb: Bool { self == .jg023 }
}

struct TrackState: Codable, Sendable, Equatable, Identifiable {
    var id: Int
    var engine: String?
    var volume: Int?
    var reverb: Int?
    var muted = false
    var soloed = false
    var rerollSeed: UInt32?
    var engineOverride: Int?
    var active = false
}

struct PatchSnapshot: Codable, Sendable, Equatable {
    var seed: UInt32?
    var firmware: FirmwareProfile = .unknown
    var tempo: Int?
    var root: Int?
    var octave: Int = 4
    var scale: Int?
    var type: Int?
    var generationMask: Int?
    var masterVolume: Int?
    var masterReverb: Int?
    var tracks: [TrackState] = (0..<4).map { TrackState(id: $0) }
    var locks: DeviceLocks?
    var reverbParameters: [Int: Int] = [:]
    var preservedCSV: [String: String] = [:]
    var capturedAt = Date()
    var seedHex: String { seed.map { String($0, radix: 16, uppercase: true).leftPadded(to: 8) } ?? "—" }
    var recallDescription: String {
        if firmware == .unknown { return "Unverified firmware" }
        if firmware == .official14 {
            if tracks.contains(where: { $0.engineOverride != nil }) { return "Off-seed · approximate recall" }
            return "Seed + saved controls"
        }
        return "Seed + JG edits"
    }
}

extension String {
    func leftPadded(to length: Int) -> String { String(repeating: "0", count: max(0, length - count)) + self }
}

enum RNDProtocolCodec {
    static let header: [UInt8] = [0xF0, 0x6F, 0x62, 0x78]
    static let engines = ["Subtractive", "FM", "Acid (303)", "Noise", "Speech", "Plucked String", "SuperSaw", "Harmonic"]
    static let roots = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
    static let scales = ["Major", "Minor", "Harmonic Minor", "Blues", "Major Pentatonic", "Minor Pentatonic", "Dorian", "Phrygian", "Lydian", "Mixolydian", "Locrian", "Whole Tone", "Double Harmonic", "Hungarian Minor", "Phrygian Dominant", "Hirajoshi", "In Sen", "Prometheus", "Octatonic", "Persian"]
    static let intervals = [[0,2,4,5,7,9,11], [0,2,3,5,7,8,10], [0,2,3,5,7,8,11], [0,3,5,6,7,10], [0,2,4,7,9], [0,3,5,7,10], [0,2,3,5,7,9,10], [0,1,3,5,7,8,10], [0,2,4,6,7,9,11], [0,2,4,5,7,9,10], [0,1,3,5,6,8,10], [0,2,4,6,8,10], [0,1,4,5,7,8,11], [0,2,3,6,7,8,11], [0,1,4,5,7,8,10], [0,2,3,7,8], [0,1,5,7,10], [0,2,4,6,9,10], [0,2,3,5,6,8,9,11], [0,1,4,5,6,8,11]]
    static let scaleMidpoints = [3,9,16,22,28,35,41,48,54,60,67,73,80,86,92,99,105,112,118,124]
    static func message(_ command: UInt8, _ payload: [UInt8] = []) -> [UInt8] { header + [command] + payload + [0xF7] }
    static func packed(_ value: UInt32) -> [UInt8] { (0..<5).map { UInt8((value >> ($0 * 7)) & ($0 == 4 ? 15 : 127)) } }
    static func unpack(_ data: ArraySlice<UInt8>) -> UInt32 {
        data.prefix(5).enumerated().reduce(0) { $0 | (UInt32($1.element & ($1.offset == 4 ? 15 : 127)) << ($1.offset * 7)) }
    }
    static func cc(_ controller: Int, _ value: Int, channel: Int = 1) -> [UInt8] {
        [UInt8(0xB0 | min(15, max(0, channel - 1))), UInt8(clamping: controller.clamped(0...127)), UInt8(clamping: value.clamped(0...127))]
    }
    static func scaleCC(_ index: Int, firmware: FirmwareProfile) -> Int {
        let index = index.clamped(0...19)
        return firmware == .jg023 ? scaleMidpoints[index] : index + 1
    }
    static func typeCC(_ index: Int, firmware: FirmwareProfile) -> Int {
        firmware == .jg023 ? 1 << index.clamped(0...2) : index.clamped(0...2) + 1
    }
    static func tempo(_ bpm: Int, firmware: FirmwareProfile, snapshot: PatchSnapshot) -> [UInt8]? {
        if firmware == .official14 {
            let value = bpm.clamped(20...400)
            return message(0x1D, [UInt8(value & 127), UInt8(value >> 7)])
        }
        guard firmware == .jg023, let root = snapshot.root, let scale = snapshot.scale, let type = snapshot.type else { return nil }
        let value = bpm.clamped(50...200)
        return message(0x21, [UInt8(type), UInt8(value & 127), UInt8(value >> 7), UInt8(root), UInt8(scale)])
    }
    static func engine(_ index: Int, track: Int, firmware: FirmwareProfile) -> [UInt8]? {
        guard (0..<4).contains(track), engines.indices.contains(index) else { return nil }
        if firmware == .jg023 { return message(0x19, [UInt8(track), UInt8(index)]) }
        // Official firmware accepts ASCII engine locks, not JG engine indexes.
        let names = engines
        if firmware == .official14 { return message(0x1B, [UInt8(track)] + Array(names[index].utf8) + [0]) }
        return nil
    }
    /// Scale degree to note; degrees past the scale length climb octaves.
    static func degreeNote(_ step: Int, root: Int, scale: Int, octave: Int) -> Int {
        let notes = intervals[scale.clamped(0...19)]
        let step = max(0, step)
        return ((octave + 1) * 12 + root + notes[step % notes.count] + 12 * (step / notes.count)).clamped(0...127)
    }
    static func quantizedNote(x: Double, root: Int, scale: Int, octave: Int) -> Int {
        let notes = intervals[scale.clamped(0...19)]
        let step = Int((x.clamped(0...1) * Double(notes.count * 2 - 1)).rounded())
        return ((octave + 1) * 12 + root + (step / notes.count) * 12 + notes[step % notes.count]).clamped(0...127)
    }
}

extension Comparable {
    func clamped(_ range: ClosedRange<Self>) -> Self { min(range.upperBound, max(range.lowerBound, self)) }
}
