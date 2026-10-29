import Foundation
import Observation
@preconcurrency import AVFoundation
import AudioToolbox

@MainActor @Observable final class AudioMonitor {
    private(set) var running = false
    private(set) var status = "Monitoring off"
    var error: String?
    var outputID: UInt32 = 0
    var gain: Float = 0.4 {
        didSet {
            #if os(macOS)
            macMonitor?.setGain(gain)
            #else
            engine?.mainMixerNode.outputVolume=gain.clamped(0...1)
            #endif
        }
    }
    private var engine: AVAudioEngine?
    private var observers: [NSObjectProtocol] = []
    private var starting = false
    private var generation = 0
    private(set) var captureStats=AudioCaptureStats()
    #if os(macOS)
    private var macMonitor: MacAudioMonitor?
    var outputs: [AudioDeviceChoice] { AudioDeviceChoice.available(input:false) }
    #endif
    init() {
        #if os(iOS)
        for name in [AVAudioSession.routeChangeNotification,AVAudioSession.interruptionNotification] {
            observers.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in
                Task { @MainActor in
                    guard let self,self.running else { return }
                    self.stop(); self.error="Audio route changed. Start monitoring again when your output is ready."
                }
            })
        }
        #endif
    }
    func start(profile: FirmwareProfile) async {
        guard !running,!starting else { return }
        generation += 1; let operation=generation
        starting=true; defer { if generation == operation { starting=false } }
        guard profile != .unknown else { error="Choose the connected firmware before monitoring."; return }
        status="Requesting audio access"
        #if os(iOS)
        let allowed=await AVAudioApplication.requestRecordPermission()
        #else
        let allowed=await AVCaptureDevice.requestAccess(for:.audio)
        #endif
        guard generation == operation else { return }
        guard allowed else { error="Allow audio input access in Settings to monitor RND."; return }
        do {
            status="Preparing audio route"
            captureStats=AudioCaptureStats()
            let dry:Bool
            #if os(macOS)
            let monitor=MacAudioMonitor(); macMonitor=monitor
            monitor.onRouteLost = { [weak self] in self?.stop(); self?.error="Audio device disconnected." }
            dry=try await monitor.start(output:outputID == 0 ? AudioDeviceChoice.defaultOutput : outputID,gain:gain,stats:captureStats)
            #else
            let session=AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord,mode:.measurement,options:[.defaultToSpeaker,.allowBluetoothA2DP])
            guard let input=session.availableInputs?.first(where:{$0.portType == .usbAudio && $0.portName.localizedCaseInsensitiveContains("rnd")}) else { throw MonitorError.route("Connect RND USB audio before monitoring.") }
            try session.setPreferredInput(input); try session.setPreferredIOBufferDuration(0.0058); try session.setActive(true)
            guard session.currentRoute.inputs.contains(where:{$0.uid == input.uid}) else { throw MonitorError.route("RND USB input is unavailable on this route.") }
            let engine=AVAudioEngine(); self.engine=engine
            let format=engine.inputNode.outputFormat(forBus:0); dry=format.channelCount == 4
            guard format.sampleRate > 0,format.channelCount >= (dry ? 4 : 6) else { throw MonitorError.route("Unsupported RND channel layout.") }
            try await AudioChannelRouter.connect(engine:engine,sampleRate:format.sampleRate,inputOffset:0,dry:dry,stats:captureStats)
            engine.mainMixerNode.outputVolume=gain
            #endif
            guard generation == operation else {
                #if os(macOS)
                monitor.stop()
                #else
                engine.stop()
                #endif
                return
            }
            running=true; error=nil; status=dry ? "Dry stem sum · monitoring" : "Stereo mix · monitoring"
        } catch {
            guard generation == operation else { return }
            stop(); self.error=error.localizedDescription
        }
    }
    func stop() {
        generation += 1; starting=false
        engine?.stop(); engine=nil; running=false; status="Monitoring off"
        #if os(macOS)
        macMonitor?.stop(); macMonitor=nil
        #else
        try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)
        #endif
    }
    enum MonitorError: LocalizedError { case route(String)
        var errorDescription:String? { if case .route(let text)=self { text } else { nil } }
    }
}
