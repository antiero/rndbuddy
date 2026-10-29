#if os(macOS)
import AVFoundation
import Testing
@testable import rndbuddy

struct AudioRenderTests {
    @Test func mapsInterleavedChannelsSilencesUnusedOutputsAndRampsGain() throws {
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: true))
        let input = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))
        let output = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))
        input.frameLength = 512; output.frameLength = 512
        for frame in 0..<512 {
            input.floatChannelData![0][frame * 2] = 0.8
            input.floatChannelData![0][frame * 2 + 1] = -0.4
        }
        let renderer = MacAudioRender(stats: AudioCaptureStats(), recording: AudioRecordingSink(), offset: 0, dry: false, rate: 48_000)
        renderer.gain.store(Float(0.5).bitPattern, ordering: .relaxed)
        renderer.render(input: input.audioBufferList, output: output.mutableAudioBufferList, time: AudioTimeStamp())
        #expect(abs(output.floatChannelData![0][0]) < 0.00001)
        #expect(abs(output.floatChannelData![0][1022] - 0.4) < 0.00001)
        #expect(abs(output.floatChannelData![0][1023] + 0.2) < 0.00001)
        renderer.gain.store(Float(0).bitPattern, ordering: .relaxed)
        renderer.render(input: input.audioBufferList, output: output.mutableAudioBufferList, time: AudioTimeStamp())
        #expect(abs(output.floatChannelData![0][0] - 0.4) < 0.00001)
        #expect(abs(output.floatChannelData![0][1022]) < 0.00001)
    }
    @Test func planarOffsetMixAndTimelineDiagnostics() throws {
        let layout = try #require(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | 6))
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channelLayout: layout)
        let input = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))
        let output = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))
        input.frameLength = 512; output.frameLength = 512
        for channel in 0..<6 {
            for frame in 0..<512 { input.floatChannelData![channel][frame] = Float(channel + 1) * 0.1 }
        }
        let stats = AudioCaptureStats()
        let renderer = MacAudioRender(stats: stats, recording: AudioRecordingSink(), offset: 2, dry: true, rate: 48_000)
        renderer.gain.store(Float(1).bitPattern, ordering: .relaxed)
        var time = AudioTimeStamp(); time.mFlags = .sampleTimeValid
        renderer.render(input: input.audioBufferList, output: output.mutableAudioBufferList, time: time)
        time.mSampleTime = 512
        renderer.render(input: input.audioBufferList, output: output.mutableAudioBufferList, time: time)
        #expect(abs(output.floatChannelData![0][256] - 0.45) < 0.00001)
        #expect(output.floatChannelData![0][256] == output.floatChannelData![1][256])
        #expect(output.floatChannelData![2][256] == 0)
        #expect(stats.frameCount == 1024)
        #expect(renderer.diagnostics.sampleTimeGaps == 0)
        time.mSampleTime = 2048
        renderer.render(input: input.audioBufferList, output: output.mutableAudioBufferList, time: time)
        #expect(renderer.diagnostics.sampleTimeGaps == 1)
    }
}
#endif
