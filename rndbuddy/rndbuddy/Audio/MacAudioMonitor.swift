#if os(macOS)
import CoreAudio
import Foundation
import Synchronization

/// A single private aggregate provides one drift-corrected I/O callback. Its
/// native float buffers are copied directly; there is no resampling queue or
/// AVAudioEngine device-switch race in the Mac path.
@MainActor final class MacAudioMonitor {
    private var aggregate: AudioDeviceID = 0
    private var io: AudioDeviceIOProcID?
    private var state: MacAudioRender?
    var diagnostics: AudioRenderDiagnostics? { state?.diagnostics }
    private(set) var routeDescription = ""
    private var activity: NSObjectProtocol?
    private let notificationQueue = DispatchQueue(label: "rndbuddy.audio.devices", qos: .utility)
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var overloadListener: AudioObjectPropertyListenerBlock?
    var onRouteLost: (() -> Void)?
    func start(output:AudioDeviceID,gain:Float,stats:AudioCaptureStats,recording:AudioRecordingSink) async throws -> Bool {
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
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var rate = 0.0; var size = UInt32(MemoryLayout<Double>.size)
        guard AudioObjectGetPropertyData(aggregate, &address, 0, nil, &size, &rate) == noErr, rate > 0 else { throw AudioMonitor.MonitorError.route("Could not read the capture sample rate.") }
        recording.sampleRate = rate
        let state = MacAudioRender(stats:stats,recording:recording,offset:offset,dry:dry,rate:rate); state.gain.store(gain.bitPattern,ordering:.relaxed); self.state=state
        var proc: AudioDeviceIOProcID?
        var result = AudioDeviceCreateIOProcIDWithBlock(&proc,aggregate,nil,Self.renderBlock(state))
        guard result == noErr, let proc else { throw AudioMonitor.MonitorError.route("Could not prepare monitoring (\(result)).") }
        io=proc
        result=AudioDeviceStart(aggregate,proc)
        guard result == noErr else { throw AudioMonitor.MonitorError.route("Could not start monitoring (\(result)).") }
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical], reason: "RND USB audio capture")
        var deviceAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let listener = Self.routeListener(owner: self, input: input.id, output: output)
        deviceListener = listener
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &deviceAddress, notificationQueue, listener)
        var overloadAddress = AudioObjectPropertyAddress(mSelector: kAudioDeviceProcessorOverload, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let overload = Self.overloadListener(state)
        overloadListener = overload
        AudioObjectAddPropertyListenerBlock(aggregate, &overloadAddress, notificationQueue, overload)
        var bufferAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyBufferFrameSize, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var bufferFrames: UInt32 = 0; var bufferSize = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(aggregate, &bufferAddress, 0, nil, &bufferSize, &bufferFrames)
        routeDescription = "\(input.name) → \(AudioDeviceChoice.text(output, selector: kAudioObjectPropertyName)); \(rate) Hz; \(bufferFrames) frames; drift compensation on input"
        return dry
    }
    func setGain(_ gain:Float) { state?.gain.store(gain.clamped(0...1).bitPattern,ordering:.relaxed) }
    func stop() {
        if let activity { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
        if let deviceListener {
            var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, notificationQueue, deviceListener)
            self.deviceListener = nil
        }
        if let overloadListener {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDeviceProcessorOverload, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            AudioObjectRemovePropertyListenerBlock(aggregate, &address, notificationQueue, overloadListener)
            self.overloadListener = nil
        }
        if let io { AudioDeviceStop(aggregate,io); AudioDeviceDestroyIOProcID(aggregate,io) }
        io=nil; state=nil
        if aggregate != 0 { AudioHardwareDestroyAggregateDevice(aggregate); aggregate=0 }
    }
    nonisolated private static func renderBlock(_ state: MacAudioRender) -> AudioDeviceIOBlock {
        { _, input, inputTime, output, _ in state.render(input: input, output: output, time: inputTime.pointee) }
    }
    nonisolated private static func overloadListener(_ state: MacAudioRender) -> AudioObjectPropertyListenerBlock {
        { _, _ in state.diagnostics.overload() }
    }
    nonisolated private static func routeListener(owner: MacAudioMonitor, input: AudioDeviceID, output: AudioDeviceID) -> AudioObjectPropertyListenerBlock {
        { [weak owner] _, _ in
            Task { @MainActor in
                guard let owner else { return }
                if !AudioDeviceChoice.available(input: true).contains(where: { $0.id == input }) ||
                    !AudioDeviceChoice.available(input: false).contains(where: { $0.id == output }) { owner.onRouteLost?() }
            }
        }
    }
    private static func isFloatDevice(_ device:AudioDeviceID,input:Bool) -> Bool {
        var address=AudioObjectPropertyAddress(mSelector:kAudioDevicePropertyStreamFormat,mScope:input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,mElement:kAudioObjectPropertyElementMain)
        var format=AudioStreamBasicDescription(); var size=UInt32(MemoryLayout.size(ofValue:format))
        guard AudioObjectGetPropertyData(device,&address,0,nil,&size,&format) == noErr else { return false }
        return format.mFormatID == kAudioFormatLinearPCM && format.mBitsPerChannel == 32 && format.mFormatFlags & kAudioFormatFlagIsFloat != 0
    }
}
#endif
