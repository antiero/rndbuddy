import Foundation
import Testing
@testable import rndbuddy

/// Opt in with TEST_RUNNER_RNDBUDDY_HARDWARE=1. No controls, notes,
/// generation, recall or firmware operations are sent by this test.
@MainActor struct HardwareTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["RNDBUDDY_HARDWARE"] == "1"))
    func connectedRNDPatchReadIsStable() async throws {
        let session = DeviceSession()
        defer { session.connect(nil) }
        for _ in 0..<60 {
            if session.snapshot.seed != nil && session.snapshot.firmware != .unknown && session.snapshot.tempo != nil { break }
            try await Task.sleep(for:.milliseconds(50))
        }
        #expect(session.connected)
        let seed = try #require(session.snapshot.seed)
        #expect(session.snapshot.firmware == .jg023)
        #expect(session.snapshot.root != nil)
        #expect(session.snapshot.scale != nil)
        #expect(session.snapshot.tracks.contains(where: { $0.active && $0.engine != nil }))
        session.requestSnapshot()
        try await Task.sleep(for:.milliseconds(300))
        #expect(session.snapshot.seed == seed)
        let data = try JSONEncoder().encode(session.snapshot)
        print("RNDBUDDY_READ_ONLY_HARDWARE",String(decoding:data,as:UTF8.self))
    }
    #if os(macOS)
    @Test(.enabled(if: ProcessInfo.processInfo.environment["RNDBUDDY_AUDIO"] == "1"))
    func nativeAudioGraphStartsSilently() async throws {
        let monitor = AudioMonitor(); monitor.gain = 0
        defer { monitor.stop() }
        let startup = Task { await monitor.start(profile:.jg023) }
        for _ in 0..<10 {
            try await Task.sleep(for:.seconds(1))
            print("RNDBUDDY_AUDIO_PHASE",monitor.status)
            if monitor.running || monitor.error != nil { break }
        }
        await startup.value
        print("RNDBUDDY_AUDIO",monitor.status,monitor.error ?? "no error")
        #expect(monitor.running)
        try await Task.sleep(for:.seconds(2))
        #expect(monitor.running)
        #expect(monitor.captureStats.frameCount > 0)
        print("RNDBUDDY_AUDIO_CAPTURE",monitor.captureStats.frameCount,monitor.captureStats.peak)
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["RNDBUDDY_AUDIO_DIAGNOSTICS"] == "1"))
    func audioSurvivesMainActorStalls() async throws {
        let monitor = AudioMonitor(); monitor.gain = 0
        defer { monitor.stop() }
        await monitor.start(profile: .jg023)
        #expect(monitor.running)
        let diagnostics = try #require(monitor.renderDiagnostics)
        print("RNDBUDDY_AUDIO_ROUTE", monitor.audioRouteDescription)
        // Deliberate main-actor stalls, interspersed with normal run-loop work.
        // No notes, patch changes or speaker audio are produced by this test.
        let end = Date.now.addingTimeInterval(60)
        var stalls = 0
        while Date.now < end {
            let until = Date.now.addingTimeInterval(0.06)
            while Date.now < until { _ = sqrt(Double(stalls + 1)) }
            stalls += 1
            try await Task.sleep(for: .milliseconds(100))
        }
        print("RNDBUDDY_AUDIO_STRESS", "mainActorStalls=", stalls, diagnostics.snapshot)
        #expect(monitor.running)
        #expect(monitor.captureStats.frameCount > 48_000 * 50)
        #expect(diagnostics.deadlineMisses == 0)
        #expect(diagnostics.sampleTimeGaps == 0)
    }
    #endif
}
