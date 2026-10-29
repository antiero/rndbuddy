import Foundation
import AudioToolbox
import AVFoundation
import Synchronization

/// One audio producer owns scratch memory. Control-side file changes disable
/// ingestion and wait for the current callback before disposing the file.
/// ExtAudioFile's primed async writer owns its bounded disk-writing queue.
final class AudioRecordingSink: @unchecked Sendable {
    private let enabled = Atomic<Bool>(false)
    private let busy = Atomic<Bool>(false)
    private let failure = Atomic<Int32>(0)
    private let frames = Atomic<UInt64>(0)
    private var file: ExtAudioFileRef?
    private let scratch = UnsafeMutablePointer<Float>.allocate(capacity: 8192 * 2)
    var sampleRate = 48_000.0 // Set before starting the audio producer.
    var writtenFrames: UInt64 { frames.load(ordering: .relaxed) }
    var writeError: OSStatus { failure.load(ordering: .relaxed) }
    deinit { finish(); scratch.deallocate() }

    func begin(url: URL) throws {
        finish()
        var format = AudioStreamBasicDescription(mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8, mChannelsPerFrame: 2,
            mBitsPerChannel: 32, mReserved: 0)
        var result = ExtAudioFileCreateWithURL(url as CFURL, kAudioFileWAVEType, &format, nil, 0, &file)
        guard result == noErr, let file else { throw RecordingError.status(result) }
        result = ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat,
            UInt32(MemoryLayout.size(ofValue: format)), &format)
        if result == noErr { result = ExtAudioFileWriteAsync(file, 0, nil) }
        guard result == noErr else { finish(); throw RecordingError.status(result) }
        failure.store(0, ordering: .relaxed)
        frames.store(0, ordering: .relaxed)
        enabled.store(true, ordering: .sequentiallyConsistent)
    }
    @discardableResult func finish() -> OSStatus {
        enabled.store(false, ordering: .sequentiallyConsistent)
        while busy.load(ordering: .sequentiallyConsistent) { Thread.sleep(forTimeInterval: 0.0002) }
        guard let file else { return noErr }
        self.file = nil
        return ExtAudioFileDispose(file)
    }
    func receive(_ buffers: UnsafeMutableAudioBufferListPointer, frames count: Int, offset: Int = 0, dry: Bool = false) {
        busy.store(true, ordering: .sequentiallyConsistent)
        defer { busy.store(false, ordering: .sequentiallyConsistent) }
        guard enabled.load(ordering: .sequentiallyConsistent), let file else { return }
        guard count <= 8192 else {
            failure.store(kAudio_ParamError, ordering: .relaxed)
            enabled.store(false, ordering: .sequentiallyConsistent); return
        }
        StereoAudioMixer.mix(buffers, frames: count, offset: offset, dry: dry, into: scratch)
        write(file: file, samples: scratch, count: count)
    }
    func receiveInterleaved(_ samples: UnsafeMutablePointer<Float>, frames count: Int) {
        busy.store(true, ordering: .sequentiallyConsistent)
        defer { busy.store(false, ordering: .sequentiallyConsistent) }
        guard enabled.load(ordering: .sequentiallyConsistent), let file else { return }
        write(file: file, samples: samples, count: count)
    }
    private func write(file: ExtAudioFileRef, samples: UnsafeMutablePointer<Float>, count: Int) {
        var list = AudioBufferList(mNumberBuffers: 1,
            mBuffers: AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(count * 8), mData: samples))
        let result = ExtAudioFileWriteAsync(file, UInt32(count), &list)
        if result == noErr { frames.wrappingAdd(UInt64(count), ordering: .relaxed) }
        else {
            failure.store(result, ordering: .relaxed)
            enabled.store(false, ordering: .sequentiallyConsistent)
        }
    }
    enum RecordingError: LocalizedError {
        case status(OSStatus)
        var errorDescription: String? { if case .status(let code) = self { "Couldn’t write the recording (\(code))." } else { nil } }
    }
}
