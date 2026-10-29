import Foundation

struct MIDIStreamParser: Sendable {
    private var running: UInt8?
    private var message: [UInt8] = []
    private var sysex: [UInt8]?
    private var discardingSysEx = false
    static let maxSysEx = 1_048_576

    mutating func reset() { self = Self() }
    mutating func consume(_ bytes: [UInt8]) -> [[UInt8]] {
        var output: [[UInt8]] = []
        for byte in bytes {
            if byte >= 0xF8 { output.append([byte]); continue }
            if discardingSysEx {
                if byte == 0xF7 { discardingSysEx = false }
                else if byte == 0xF0 { discardingSysEx = false; sysex = [byte] }
                continue
            }
            if sysex != nil {
                if byte == 0xF7 { sysex?.append(byte); if let complete = sysex { output.append(complete) }; sysex = nil; continue }
                if byte < 0x80 {
                    if (sysex?.count ?? 0) < Self.maxSysEx { sysex?.append(byte) }
                    else { sysex = nil; discardingSysEx = true }
                    continue
                }
                sysex = nil // Interrupted malformed transfer is discarded, never synthetically completed.
            }
            if byte == 0xF0 { sysex = [byte]; running = nil; message = []; continue }
            if byte & 0x80 != 0 {
                message = [byte]
                running = byte < 0xF0 ? byte : nil
                if Self.length(byte) == 1 { output.append(message); message = [] }
                continue
            }
            if message.isEmpty, let running { message = [running] }
            guard let status = message.first else { continue }
            message.append(byte)
            if message.count == Self.length(status) { output.append(message); message = [] }
        }
        return output
    }
    static func length(_ status: UInt8) -> Int {
        if status < 0xF0 { return status & 0xE0 == 0xC0 ? 2 : 3 }
        switch status { case 0xF1, 0xF3: return 2; case 0xF2: return 3; default: return 1 }
    }
    static func valid(_ data: [UInt8]) -> Bool {
        guard let status = data.first, status >= 0x80 else { return false }
        if status == 0xF0 { return data.count >= 2 && data.count <= maxSysEx && data.last == 0xF7 && data.dropFirst().dropLast().allSatisfy { $0 < 128 } }
        return data.count == length(status) && data.dropFirst().allSatisfy { $0 < 128 }
    }
}
