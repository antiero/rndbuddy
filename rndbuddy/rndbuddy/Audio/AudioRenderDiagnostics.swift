import Foundation
import Synchronization
import CoreAudio

/// Numeric counters only. No logging, tasks, allocation or UI in callbacks.
final class AudioRenderDiagnostics: Sendable {
    private let calls = Atomic<UInt64>(0)
    private let maximumTicks = Atomic<UInt64>(0)
    private let late = Atomic<UInt64>(0)
    private let gaps = Atomic<UInt64>(0)
    private let overloads = Atomic<UInt64>(0)
    private let invalid = Atomic<UInt64>(0)
    private let totalTicks = Atomic<UInt64>(0)
    let nanosecondsPerTick: Double
    init() {
        var info = mach_timebase_info_data_t(); mach_timebase_info(&info)
        nanosecondsPerTick = Double(info.numer) / Double(info.denom)
    }
    var snapshot: String {
        let count = calls.load(ordering: .relaxed)
        let maximum = Double(maximumTicks.load(ordering: .relaxed)) * nanosecondsPerTick / 1e6
        let average = Double(totalTicks.load(ordering: .relaxed)) * nanosecondsPerTick / 1e6 / Double(max(1, count))
        return "callbacks=\(count) meanMs=\(average) maxMs=\(maximum) deadlineMisses=\(late.load(ordering: .relaxed)) sampleTimeGaps=\(gaps.load(ordering: .relaxed)) HALOverloads=\(overloads.load(ordering: .relaxed)) oversized=\(invalid.load(ordering: .relaxed))"
    }
    var deadlineMisses: UInt64 { late.load(ordering: .relaxed) }
    var sampleTimeGaps: UInt64 { gaps.load(ordering: .relaxed) }
    func record(ticks: UInt64, frames: Int, rate: Double) {
        calls.wrappingAdd(1, ordering: .relaxed)
        totalTicks.wrappingAdd(ticks, ordering: .relaxed)
        maximumTicks.max(ticks, ordering: .relaxed)
        if Double(ticks) * nanosecondsPerTick > Double(frames) / rate * 1e9 { late.wrappingAdd(1, ordering: .relaxed) }
    }
    func gap() { gaps.wrappingAdd(1, ordering: .relaxed) }
    func overload() { overloads.wrappingAdd(1, ordering: .relaxed) }
    func oversized() { invalid.wrappingAdd(1, ordering: .relaxed) }
}
