import Synchronization
import AVFoundation

final class AudioCaptureStats: Sendable {
    private let frames = Atomic<UInt64>(0)
    private let peakBits = Atomic<UInt32>(0)
    var frameCount: UInt64 { frames.load(ordering:.relaxed) }
    var peak: Float { Float(bitPattern:peakBits.load(ordering:.relaxed)) }
    func record(frames count:UInt64,peak:Float) {
        frames.wrappingAdd(count,ordering:.relaxed); peakBits.store(peak.bitPattern,ordering:.relaxed)
    }
    func receive(_ buffer: AVAudioPCMBuffer) {
        frames.wrappingAdd(UInt64(buffer.frameLength),ordering:.relaxed)
        guard let data = buffer.floatChannelData else { return }
        var peak: Float = 0
        for channel in 0..<Int(buffer.format.channelCount) {
            for frame in 0..<Int(buffer.frameLength) { peak = max(peak,abs(data[channel][frame])) }
        }
        peakBits.store(peak.bitPattern,ordering:.relaxed)
    }
}
