// JG CSV compatibility adapts jgharding/JG-RND (MIT, copyright 2026 jgharding).
// Full upstream licence: docs/ThirdPartyNotices.md in the app project.
import Foundation

struct PatchDocument: Codable, Sendable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var tags = ""
    var favourite = false
    var modifiedAt = Date()
    var snapshot: PatchSnapshot
}
struct MappingDocument: Codable, Sendable, Equatable, Identifiable {
    var id=UUID()
    var name:String
    var modifiedAt=Date()
    var mapping:PerformanceMapping
}
struct PatchArchive: Codable, Sendable {
    var version = 1
    var patches: [PatchDocument]
    var mappings: [MappingDocument]?
    var pages: [PerformancePage]?
    static func decode(_ data: Data) throws -> Self {
        let result = try JSONDecoder().decode(Self.self, from: data)
        guard result.version == 1, result.patches.count <= 10_000 else { throw ArchiveError.invalid }
        for patch in result.patches { try validate(patch.snapshot) }
        guard (result.mappings?.count ?? 0) <= 1_000 else { throw ArchiveError.invalid }
        for mapping in result.mappings ?? [] {
            for axis in [mapping.mapping.x,mapping.mapping.y] {
                guard [axis.minimum,axis.maximum,axis.smoothing,axis.deadZone].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { throw ArchiveError.invalid }
            }
        }
        guard (result.pages?.count ?? 0) <= 1_000 else { throw ArchiveError.invalid }
        for page in result.pages ?? [] { try page.validate() }
        return result
    }
    static func validate(_ snapshot: PatchSnapshot) throws {
        guard snapshot.seed != nil, snapshot.tracks.count == 4,
              snapshot.tracks.map(\.id) == [0,1,2,3],
              snapshot.root.map({ (0...11).contains($0) }) ?? true,
              snapshot.scale.map({ (0...19).contains($0) }) ?? true,
              snapshot.type.map({ (0...2).contains($0) }) ?? true,
              snapshot.generationMask.map({ (1...7).contains($0) }) ?? true,
              (-1...8).contains(snapshot.octave),
              snapshot.tempo.map({ (20...400).contains($0) }) ?? true else { throw ArchiveError.invalid }
        if let locks = snapshot.locks {
            guard locks.engines.count == 4, locks.engines.compactMap({ $0 }).allSatisfy({ (0..<8).contains($0) }),
                  locks.type.map({ (0...2).contains($0) }) ?? true,
                  locks.root.map({ (0...11).contains($0) }) ?? true,
                  locks.scale.map({ (0...19).contains($0) }) ?? true,
                  locks.tracks.map({ (1...4).contains($0) }) ?? true,
                  (-3...3).contains(locks.rootOctave) else { throw ArchiveError.invalid }
        }
        let controls = [snapshot.masterVolume, snapshot.masterReverb] + snapshot.tracks.flatMap { [$0.volume, $0.reverb] }
        guard controls.compactMap({ $0 }).allSatisfy({ (0...127).contains($0) }),
              snapshot.tracks.allSatisfy({ $0.engineOverride.map { (0..<8).contains($0) } ?? true }),
              snapshot.reverbParameters.allSatisfy({ (85...90).contains($0.key) && (0...127).contains($0.value) }) else { throw ArchiveError.invalid }
    }
    enum ArchiveError: LocalizedError { case invalid
        var errorDescription: String? { "This patch file contains unsupported or invalid data." }
    }
}

enum PatchCSV {
    static let columns = ["SYSEX", "PATCH NAME"] + (1...4).flatMap { n in ["VOLUME", "REVERB", "MUTE", "SOLO", "ENGINE", "REROLL"].map { "CH \(n) \($0)" } } + ["MASTER REVERB MULTIPLIER", "MASTER VOLUME", "REVERB PRE-DELAY", "REVERB TONE", "REVERB DIFFUSION 1", "REVERB DIFFUSION 2", "REVERB ROOM SIZE", "REVERB DECAY", "TEMPO BPM", "KEY ROOT NOTE", "KEY ROOT OCTAVE", "MUSICAL SCALE", "TAGS"]
    static func rows(_ text: String) throws -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
        let chars = Array(text); var index = 0
        while index < chars.count {
            let char = chars[index]
            if char == "\"" {
                if quoted && index + 1 < chars.count && chars[index + 1] == "\"" { field.append("\""); index += 1 }
                else { quoted.toggle() }
            } else if char == "," && !quoted { row.append(field); field = "" }
            else if (char == "\n" || char == "\r\n" || char == "\r") && !quoted {
                row.append(field); if row.contains(where: { !$0.isEmpty }) { rows.append(row) }; row = []; field = ""
            } else { field.append(char) }
            index += 1
        }
        guard !quoted else { throw PatchArchive.ArchiveError.invalid }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
    static func decode(_ text: String) throws -> [PatchDocument] {
        let rows = try rows(text)
        guard let header = rows.first, header.contains("SYSEX"), header.contains("PATCH NAME"), Set(header).count == header.count, rows.count <= 10_001 else { throw PatchArchive.ArchiveError.invalid }
        return try rows.dropFirst().map { row in
            guard row.count <= header.count else { throw PatchArchive.ArchiveError.invalid }
            let fields = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($0.element, $0.offset < row.count ? row[$0.offset] : "") })
            let hex = (fields["SYSEX"] ?? "").filter { !$0.isWhitespace && $0 != "," }
            guard hex.count == 22 else { throw PatchArchive.ArchiveError.invalid }
            var bytes: [UInt8] = []; var offset = hex.startIndex
            while offset < hex.endIndex {
                let end = hex.index(offset, offsetBy: 2)
                guard let byte = UInt8(hex[offset..<end], radix: 16) else { throw PatchArchive.ArchiveError.invalid }
                bytes.append(byte); offset = end
            }
            guard Array(bytes.prefix(5)) == RNDProtocolCodec.header + [0x10], MIDIStreamParser.valid(bytes), bytes[9] < 16 else { throw PatchArchive.ArchiveError.invalid }
            var snapshot = PatchSnapshot(seed: RNDProtocolCodec.unpack(bytes[5..<10]), firmware: .jg023)
            snapshot.preservedCSV = fields
            func number(_ key: String) throws -> Int? {
                guard let text = fields[key], !text.isEmpty else { return nil }
                guard let value = Int(text) else { throw PatchArchive.ArchiveError.invalid }; return value
            }
            snapshot.masterVolume = try number("MASTER VOLUME")
            snapshot.masterReverb = try number("MASTER REVERB MULTIPLIER")
            snapshot.tempo = try number("TEMPO BPM")
            snapshot.generationMask = try number("GENERATION MASK")
            snapshot.octave = try number("KEY ROOT OCTAVE") ?? 4
            if let root = fields["KEY ROOT NOTE"], !root.isEmpty {
                let names = ["C", "C#", "D", "D# / Eb", "E", "F", "F#", "G", "G#", "A", "A# / Bb", "B"]
                guard let index = names.firstIndex(of: root) ?? Int(root) else { throw PatchArchive.ArchiveError.invalid }; snapshot.root = index
            }
            if let scale = fields["MUSICAL SCALE"], !scale.isEmpty {
                guard let index = RNDProtocolCodec.scales.firstIndex(where: { $0.caseInsensitiveCompare(scale) == .orderedSame }) ?? Int(scale) else { throw PatchArchive.ArchiveError.invalid }; snapshot.scale = index
            }
            for track in 0..<4 {
                let key = "CH \(track + 1) "
                snapshot.tracks[track].volume = try number(key + "VOLUME")
                snapshot.tracks[track].reverb = try number(key + "REVERB")
                snapshot.tracks[track].muted = fields[key + "MUTE"] == "Muted"
                snapshot.tracks[track].soloed = fields[key + "SOLO"] == "Soloed"
                snapshot.tracks[track].engineOverride = try number(key + "ENGINE")
                if let reroll = fields[key + "REROLL"], let seed = reroll.split(separator: ":").dropFirst().first {
                    guard let value = UInt32(seed, radix: 16) else { throw PatchArchive.ArchiveError.invalid }; snapshot.tracks[track].rerollSeed = value
                }
            }
            for (i, name) in columns[28..<34].enumerated() { if let value = try number(name) { snapshot.reverbParameters[i + 85] = value } }
            try PatchArchive.validate(snapshot)
            return PatchDocument(name: fields["PATCH NAME"] ?? "Untitled", tags: fields["TAGS"] ?? "", snapshot: snapshot)
        }
    }
    static func encode(_ patches: [PatchDocument]) -> String {
        let extra = Set(patches.flatMap { $0.snapshot.preservedCSV.keys }).union(patches.contains(where: { $0.snapshot.generationMask != nil }) ? ["GENERATION MASK"] : []).subtracting(columns).sorted()
        let header = columns + extra
        func quote(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        return ([header] + patches.map { patch in
            let s = patch.snapshot; var f = s.preservedCSV
            f["SYSEX"] = s.seed.map { RNDProtocolCodec.message(0x10, RNDProtocolCodec.packed($0)).map { String($0, radix: 16).leftPadded(to: 2) }.joined().uppercased() } ?? ""
            f["PATCH NAME"] = patch.name; f["TAGS"] = patch.tags
            f["MASTER VOLUME"] = s.masterVolume.map(String.init) ?? ""
            f["MASTER REVERB MULTIPLIER"] = s.masterReverb.map(String.init) ?? ""
            f["TEMPO BPM"] = s.tempo.map(String.init) ?? ""
            f["GENERATION MASK"] = s.generationMask.map(String.init) ?? ""
            f["KEY ROOT NOTE"] = s.root.map { ["C","C#","D","D# / Eb","E","F","F#","G","G#","A","A# / Bb","B"][$0.clamped(0...11)] } ?? ""
            f["KEY ROOT OCTAVE"] = String(s.octave)
            f["MUSICAL SCALE"] = s.scale.map { RNDProtocolCodec.scales[$0.clamped(0...19)] } ?? ""
            for track in s.tracks {
                let key = "CH \(track.id + 1) "
                f[key + "VOLUME"] = track.volume.map(String.init) ?? ""
                f[key + "REVERB"] = track.reverb.map(String.init) ?? ""
                f[key + "MUTE"] = track.muted ? "Muted" : ""
                f[key + "SOLO"] = track.soloed ? "Soloed" : ""
                f[key + "ENGINE"] = track.engineOverride.map(String.init) ?? ""
                if let seed = track.rerollSeed { f[key + "REROLL"] = "1:" + String(seed, radix: 16).leftPadded(to: 8).uppercased() }
            }
            for (i, name) in columns[28..<34].enumerated() { f[name] = s.reverbParameters[i + 85].map(String.init) ?? "" }
            return header.map { f[$0] ?? "" }
        }).map { $0.map(quote).joined(separator: ",") }.joined(separator: "\r\n")
    }
}
