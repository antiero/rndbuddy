#if os(macOS)
import AVFoundation
import Accelerate
import Synchronization

/// A single HAL I/O producer owns the preallocated scratch, ramp and timeline.
/// The control thread touches only atomic gain; teardown waits for HAL to stop.
final class MacAudioRender: @unchecked Sendable {
    static let capacity = 8192
    let gain = Atomic<UInt32>(0)
    let diagnostics = AudioRenderDiagnostics()
    private let stereo = UnsafeMutablePointer<Float>.allocate(capacity: capacity * 2)
    private let ramp = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
    private let stats: AudioCaptureStats
    private let recording: AudioRecordingSink
    private let offset: Int
    private let dry: Bool
    private let rate: Double
    private var previousGain: Float = 0
    private var expectedInputTime: Double?
    init(stats: AudioCaptureStats, recording: AudioRecordingSink, offset: Int, dry: Bool, rate: Double) {
        self.stats = stats; self.recording = recording; self.offset = offset; self.dry = dry; self.rate = rate
        stereo.initialize(repeating: 0, count: Self.capacity * 2)
        ramp.initialize(repeating: 0, count: Self.capacity)
    }
    deinit { stereo.deallocate(); ramp.deallocate() }
    func render(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>, time: AudioTimeStamp) {
        let start = mach_absolute_time()
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        // Always clear all outputs, including any unused aggregate streams.
        var index = 0; var frames = 0
        while index < outputs.count {
            let buffer = outputs[index]
            if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
            if index == 0 { frames = Int(buffer.mDataByteSize) / max(1, Int(buffer.mNumberChannels) * 4) }
            index += 1
        }
        guard frames > 0, frames <= Self.capacity else { diagnostics.oversized(); return }
        if time.mFlags.contains(.sampleTimeValid) {
            if let expectedInputTime, abs(time.mSampleTime - expectedInputTime) > 0.5 { diagnostics.gap() }
            expectedInputTime = time.mSampleTime + Double(frames)
        }
        StereoAudioMixer.mix(inputs, frames: frames, offset: offset, dry: dry, into: stereo)
        var peak: Float = 0
        vDSP_maxmgv(stereo, 1, &peak, vDSP_Length(frames * 2))
        var target = Float(bitPattern: gain.load(ordering: .relaxed))
        // Smooth UI gain changes over one block to avoid discontinuities.
        vDSP_vgen(&previousGain, &target, ramp, 1, vDSP_Length(frames))
        previousGain = target
        index = 0; var base = 0
        while index < outputs.count && base < 2 {
            let buffer = outputs[index]; let channels = Int(buffer.mNumberChannels)
            if let data = buffer.mData {
                let count = min(frames, Int(buffer.mDataByteSize) / max(1, channels * 4))
                var channel = 0
                while channel < channels && base + channel < 2 {
                    vDSP_vmul(stereo + base + channel, 2, ramp, 1,
                              data.assumingMemoryBound(to: Float.self) + channel,
                              vDSP_Stride(channels), vDSP_Length(count))
                    channel += 1
                }
            }
            base += channels; index += 1
        }
        stats.record(frames: UInt64(frames), peak: peak)
        recording.receiveInterleaved(stereo, frames: frames)
        diagnostics.record(ticks: mach_absolute_time() - start, frames: frames, rate: rate)
    }
}
#endif
