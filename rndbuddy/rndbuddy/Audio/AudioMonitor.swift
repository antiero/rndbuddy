import Foundation
import Observation
@preconcurrency import AVFoundation
import AudioToolbox
#if os(macOS)
import CoreAudio
#endif

@MainActor @Observable final class AudioMonitor {
    private(set) var running = false
    private(set) var recording = false
    private(set) var monitoring = false
    private(set) var elapsed = 0.0
    private(set) var level: Float = 0
    private(set) var takes: [URL] = []
    private let recordingSink = AudioRecordingSink()
    private var meterTask: Task<Void, Never>?
    private var currentTake: URL?
    var preparing: Bool { starting }
    private(set) var status = "USB audio off"
    var error: String?
    var outputID: UInt32 = 0
    var gain: Float = 0.4 {
        didSet {
            #if os(macOS)
            macMonitor?.setGain(monitoring ? gain : 0)
            #else
            engine?.mainMixerNode.outputVolume=monitoring ? gain.clamped(0...1) : 0
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
    private(set) var outputs = AudioDeviceChoice.available(input: false)
    private var outputObserver: AudioDeviceObserver?
    var renderDiagnostics: AudioRenderDiagnostics? { macMonitor?.diagnostics }
    var audioRouteDescription: String { macMonitor?.routeDescription ?? "" }
    #endif
    static var captureDirectory: URL {
        URL.documentsDirectory.appending(path: "Captures", directoryHint: .isDirectory)
    }
    init() {
        refreshTakes()
        #if os(macOS)
        outputObserver = AudioDeviceObserver { [weak self] in
            Task { @MainActor in self?.outputs = AudioDeviceChoice.available(input: false) }
        }
        #endif
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
            dry=try await monitor.start(output:outputID == 0 ? AudioDeviceChoice.defaultOutput : outputID,gain:monitoring ? gain : 0,stats:captureStats,recording:recordingSink)
            #else
            let session=AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord,mode:.measurement,options:[.defaultToSpeaker,.allowBluetoothA2DP])
            guard let input=session.availableInputs?.first(where:{$0.portType == .usbAudio && $0.portName.localizedCaseInsensitiveContains("rnd")}) else { throw MonitorError.route("Connect RND USB audio before monitoring.") }
            try session.setPreferredInput(input); try session.setPreferredIOBufferDuration(0.0058); try session.setActive(true)
            guard session.currentRoute.inputs.contains(where:{$0.uid == input.uid}) else { throw MonitorError.route("RND USB input is unavailable on this route.") }
            let engine=AVAudioEngine(); self.engine=engine
            let format=engine.inputNode.outputFormat(forBus:0); dry=format.channelCount == 4
            guard format.sampleRate > 0,format.channelCount >= (dry ? 4 : 6) else { throw MonitorError.route("Unsupported RND channel layout.") }
            try await AudioChannelRouter.connect(engine:engine,sampleRate:format.sampleRate,inputOffset:0,dry:dry,stats:captureStats,recording:recordingSink)
            engine.mainMixerNode.outputVolume=monitoring ? gain : 0
            #endif
            guard generation == operation else {
                #if os(macOS)
                monitor.stop()
                #else
                engine.stop()
                #endif
                return
            }
            running=true; error=nil
            meterTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled, let self else { return }
                    self.level = self.captureStats.peak
                    if self.recording {
                        self.elapsed = Double(self.recordingSink.writtenFrames) / self.recordingSink.sampleRate
                        if self.recordingSink.writeError != noErr {
                            let code = self.recordingSink.writeError
                            self.stopRecording()
                            self.error = "Recording stopped because audio could not be written (\(code)). The partial take was kept."
                        }
                    }
                }
            }
            status=dry ? "Dry stem sum" : "Stereo mix"
        } catch {
            guard generation == operation else { return }
            stop(); self.error=error.localizedDescription
        }
    }
    func setMonitoring(_ enabled: Bool) {
        monitoring = enabled
        #if os(macOS)
        macMonitor?.setGain(enabled ? gain : 0)
        #else
        engine?.mainMixerNode.outputVolume = enabled ? gain : 0
        #endif
    }
    func startRecording(profile: FirmwareProfile) async {
        guard !recording, !starting else { return }
        if !running { await start(profile: profile) }
        guard running else { return }
        do {
            try FileManager.default.createDirectory(at: Self.captureDirectory, withIntermediateDirectories: true)
            let name = "RND \(Date.now.formatted(.iso8601).replacingOccurrences(of: ":", with: "-")) \(UUID().uuidString.prefix(6)).wav"
            let url = Self.captureDirectory.appending(path: name)
            try recordingSink.begin(url: url)
            currentTake = url; elapsed = 0; recording = true; error = nil
        } catch { self.error = error.localizedDescription }
    }
    func stopRecording() {
        finishRecording()
        if !monitoring { stopAudioRoute() }
    }
    private func finishRecording() {
        guard recording else { return }
        let result = recordingSink.finish()
        recording = false; currentTake = nil
        refreshTakes()
        if result != noErr { error = "The recording could not be finalised (\(result))." }
    }
    func refreshTakes() {
        takes = ((try? FileManager.default.contentsOfDirectory(at: Self.captureDirectory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "wav" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
    func stop() {
        finishRecording()
        stopAudioRoute()
    }
    private func stopAudioRoute() {
        meterTask?.cancel(); meterTask = nil; level = 0
        generation += 1; starting=false
        engine?.stop(); engine=nil; running=false; status="USB audio off"
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
