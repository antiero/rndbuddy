import AVFoundation
import Accelerate

/// Only stack values and Accelerate operations on the audio thread. Resolve
/// channel layout once per block, never scan buffer lists once per sample.
enum StereoAudioMixer {
    static func mix(_ buffers: UnsafeMutableAudioBufferListPointer, frames: Int,
                    offset: Int, dry: Bool, into stereo: UnsafeMutablePointer<Float>) {
        vDSP_vclr(stereo, 1, vDSP_Length(frames * 2))
        var source = 0
        while source < (dry ? 4 : 2) {
            var base = 0
            var index = 0
            while index < buffers.count {
                let buffer = buffers[index]
                let channels = Int(buffer.mNumberChannels)
                let channel = offset + source - base
                if channel >= 0 && channel < channels, let data = buffer.mData {
                    let count = min(frames, Int(buffer.mDataByteSize) / max(1, channels * 4))
                    let samples = data.assumingMemoryBound(to: Float.self) + channel
                    var weight: Float = dry ? 0.25 : 1
                    let target = stereo + (dry ? 0 : source)
                    vDSP_vsma(samples, vDSP_Stride(channels), &weight, target, 2, target, 2, vDSP_Length(count))
                    if dry {
                        vDSP_vsma(samples, vDSP_Stride(channels), &weight, stereo + 1, 2, stereo + 1, 2, vDSP_Length(count))
                    }
                    break
                }
                base += channels; index += 1
            }
            source += 1
        }
    }
}
