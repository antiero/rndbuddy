import Foundation

/// Official 1.4 lock packing observed in Pixels' seed suffix codec.
struct DeviceLocks: Codable, Sendable, Equatable {
    var type: Int?
    var root: Int?
    var scale: Int?
    var tracks: Int?
    var engines: [Int?] = [nil,nil,nil,nil]
    var rootOctave = 0
    static func decode(_ packed: UInt32) -> Self? {
        let value = Int(packed), base = 191_766_120
        guard value < base * 8 else { return nil }
        var remainder = value % base
        guard remainder < 35_823_060 else { return nil }
        let type = remainder % 4
        let root = remainder / 4 % 13
        let scale = remainder / 52 % 21
        let tracks = remainder / 1092 % 5
        remainder /= 5460
        var engines: [Int?] = [nil,nil,nil,nil]
        for index in (0..<4).reversed() { let digit = remainder % 9; remainder /= 9; engines[index] = digit == 0 ? nil : digit-1 }
        let octave = value / base
        return Self(type:type == 0 ? nil : type-1,root:root == 0 ? nil : root-1,scale:scale == 0 ? nil : scale-1,tracks:tracks == 0 ? nil : tracks,engines:engines,rootOctave:root == 0 || octave == 0 ? 0 : octave-4)
    }
    func messages() -> [[UInt8]] {
        var result: [[UInt8]] = []
        if let type { result.append(RNDProtocolCodec.message(0x1A,[UInt8(type.clamped(0...2))])) }
        if let root {
            let note = UInt8((60+root+12*rootOctave).clamped(0...127))
            result += [[0x90,note,100],[0x80,note,0]]
        }
        if let scale { result.append(RNDProtocolCodec.cc(9,scale+1)) }
        if let tracks { result.append(RNDProtocolCodec.message(0x1F,[UInt8(tracks.clamped(1...4))])) }
        for (track,engine) in engines.prefix(4).enumerated() {
            if let engine, let message = RNDProtocolCodec.engine(engine,track:track,firmware:.official14) { result.append(message) }
        }
        return result
    }
}
