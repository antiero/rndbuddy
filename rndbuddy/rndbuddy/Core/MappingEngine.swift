import Foundation

enum PerformanceMode: String, Codable, CaseIterable, Sendable { case modulate = "Modulate", play = "Play" }
enum InputMethod: String, CaseIterable, Sendable { case touch = "Touch", hands = "Hands", motion = "Motion" }
enum MappingTarget: String, Codable, CaseIterable, Sendable, Identifiable {
    case volume = "Track volume", reverb = "Track reverb", masterVolume = "Master volume", masterReverb = "Master reverb", tone = "Reverb tone", decay = "Reverb decay"
    var id: String { rawValue }
    var deep: Bool { self == .tone || self == .decay }
    func control(track: Int) -> (Int, Int) {
        switch self {
        case .volume: (7, track + 2)
        case .reverb: (91, track + 2)
        case .masterVolume: (7, 1)
        case .masterReverb: (91, 1)
        case .tone: (86, 1)
        case .decay: (90, 1)
        }
    }
}
struct AxisMapping: Codable, Equatable, Sendable {
    var target: MappingTarget
    var minimum = 0.0
    var maximum = 1.0
    var inverted = false
    var smoothing = 0.25
    var deadZone = 0.01
    func mapped(_ value: Double) -> Double {
        let input = inverted ? 1 - value : value
        return minimum + input.clamped(0...1) * (maximum - minimum)
    }
}
struct PerformanceMapping: Codable, Equatable, Sendable {
    var x = AxisMapping(target: .volume)
    var y = AxisMapping(target: .reverb)
}
struct MappingEngine: Sendable {
    private var previous: [MappingTarget: Double] = [:]
    mutating func value(_ input: Double, axis: AxisMapping) -> Int? {
        let target = axis.mapped(input)
        let old = previous[axis.target] ?? target
        let next = old + (target - old) * (1 - axis.smoothing.clamped(0...0.95))
        guard previous[axis.target] == nil || abs(next - old) >= axis.deadZone else { return nil }
        previous[axis.target] = next
        return Int((next * 127).rounded()).clamped(0...127)
    }
    mutating func reset() { previous.removeAll() }
}
