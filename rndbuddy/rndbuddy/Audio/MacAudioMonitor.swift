#if os(macOS)
import CoreAudio
import Foundation
import Synchronization

private final class MonitorRenderState: Sendable {
    let gain = Atomic<UInt32>(0)
    let stats: AudioCaptureStats
    init(stats:AudioCaptureStats) { self.stats=stats }
}

/// A single private aggregate provides one drift-corrected I/O callback. Its
/// native float buffers are copied directly; there is no resampling queue or
/// AVAudioEngine device-switch race in the Mac path.
@MainActor final class MacAudioMonitor {
    private var aggregate: AudioDeviceID = 0
    private var io: AudioDeviceIOProcID?
    private var state: MonitorRenderState?
    private var watch: Task<Void,Never>?
    var onRouteLost: (() -> Void)?
    func start(output:AudioDeviceID,gain:Float,stats:AudioCaptureStats) async throws -> Bool {
        guard let input = AudioDeviceChoice.available(input:true).first(where:{$0.name.localizedCaseInsensitiveContains("rnd")}) else { throw AudioMonitor.MonitorError.route("Connect RND USB audio before monitoring.") }
        guard output != 0, input.id != output else { throw AudioMonitor.MonitorError.route("Choose speakers or headphones as the output.") }
        let count = AudioDeviceChoice.channels(input.id,input:true)
        guard count == 4 || count >= 6 else { throw AudioMonitor.MonitorError.route("Unsupported RND channel layout.") }
        let dry = count == 4
        aggregate = try AudioDeviceChoice.makeAggregate(input:input.id,output:output)
        let offset = AudioDeviceChoice.channels(output,input:true)
        for _ in 0..<30 {
            if AudioDeviceChoice.channels(aggregate,input:true) >= offset+count && AudioDeviceChoice.channels(aggregate,input:false) >= 2 { break }
            try await Task.sleep(for:.milliseconds(50))
        }
        guard Self.isFloatDevice(aggregate,input:true), Self.isFloatDevice(aggregate,input:false) else { throw AudioMonitor.MonitorError.route("This output does not provide a supported 32-bit float audio route.") }
        let state = MonitorRenderState(stats:stats); state.gain.store(gain.bitPattern,ordering:.relaxed); self.state=state
        var proc: AudioDeviceIOProcID?
        var result = AudioDeviceCreateIOProcIDWithBlock(&proc,aggregate,nil,Self.render(state:state,offset:offset,dry:dry))
        guard result == noErr, let proc else { throw AudioMonitor.MonitorError.route("Could not prepare monitoring (\(result)).") }
        io=proc
        result=AudioDeviceStart(aggregate,proc)
        guard result == noErr else { throw AudioMonitor.MonitorError.route("Could not start monitoring (\(result)).") }
        watch=Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for:.seconds(1))
                guard !Task.isCancelled,let self else { return }
                if !AudioDeviceChoice.available(input:true).contains(where:{$0.id == input.id}) || !AudioDeviceChoice.available(input:false).contains(where:{$0.id == output}) {
                    self.onRouteLost?(); return
                }
            }
        }
        return dry
    }
    func setGain(_ gain:Float) { state?.gain.store(gain.clamped(0...1).bitPattern,ordering:.relaxed) }
    func stop() {
        watch?.cancel(); watch=nil
        if let io { AudioDeviceStop(aggregate,io); AudioDeviceDestroyIOProcID(aggregate,io) }
        io=nil; state=nil
        if aggregate != 0 { AudioHardwareDestroyAggregateDevice(aggregate); aggregate=0 }
    }
    private static func isFloatDevice(_ device:AudioDeviceID,input:Bool) -> Bool {
        var address=AudioObjectPropertyAddress(mSelector:kAudioDevicePropertyStreamFormat,mScope:input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,mElement:kAudioObjectPropertyElementMain)
        var format=AudioStreamBasicDescription(); var size=UInt32(MemoryLayout.size(ofValue:format))
        guard AudioObjectGetPropertyData(device,&address,0,nil,&size,&format) == noErr else { return false }
        return format.mFormatID == kAudioFormatLinearPCM && format.mBitsPerChannel == 32 && format.mFormatFlags & kAudioFormatFlagIsFloat != 0
    }
    nonisolated private static func render(state:MonitorRenderState,offset:Int,dry:Bool) -> AudioDeviceIOBlock {
        { _,input,_,output,_ in
            let inputs=UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating:input))
            let outputs=UnsafeMutableAudioBufferListPointer(output)
            let gain=Float(bitPattern:state.gain.load(ordering:.relaxed))
            func sample(channel:Int,frame:Int) -> Float {
                var base=0
                for buffer in inputs {
                    let count=Int(buffer.mNumberChannels)
                    if channel >= base && channel < base+count, let data=buffer.mData,
                       frame < Int(buffer.mDataByteSize)/max(1,count*4) {
                        return data.assumingMemoryBound(to:Float.self)[frame*count+channel-base]
                    }
                    base += count
                }
                return 0
            }
            var outputChannel=0; var frames=0; var peak:Float=0
            for buffer in outputs {
                guard let data=buffer.mData else { continue }
                let channels=Int(buffer.mNumberChannels); let count=Int(buffer.mDataByteSize)/max(1,channels*4)
                let samples=data.assumingMemoryBound(to:Float.self)
                frames=max(frames,count)
                for frame in 0..<count {
                    for channel in 0..<channels {
                        let target=outputChannel+channel
                        var value:Float=0
                        if target < 2 {
                            if dry { for source in 0..<4 { value += sample(channel:offset+source,frame:frame)*0.25 } }
                            else { value=sample(channel:offset+target,frame:frame) }
                        }
                        peak=max(peak,abs(value)); samples[frame*channels+channel]=value*gain
                    }
                }
                outputChannel += channels
            }
            state.stats.record(frames:UInt64(frames),peak:peak)
        }
    }
}
#endif
