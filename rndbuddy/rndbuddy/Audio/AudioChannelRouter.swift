import AVFoundation
import AudioToolbox

@MainActor enum AudioChannelRouter {
    /// Selects the RND pair from the native hardware stream with Apple's realtime
    /// matrix mixer. No input-bus mutation or realtime buffer allocations.
    static func connect(engine: AVAudioEngine, sampleRate: Double, inputOffset: Int, dry: Bool, stats: AudioCaptureStats) async throws {
        let source = engine.inputNode.outputFormat(forBus:0)
        guard let stereo = AVAudioFormat(standardFormatWithSampleRate:sampleRate,channels:2),
              Int(source.channelCount) >= inputOffset + (dry ? 4 : 2) else { throw AudioMonitor.MonitorError.route("Unsupported RND audio format.") }
        let description = AudioComponentDescription(componentType:kAudioUnitType_Mixer,componentSubType:kAudioUnitSubType_MatrixMixer,componentManufacturer:kAudioUnitManufacturer_Apple,componentFlags:0,componentFlagsMask:0)
        let mixer = try await AVAudioUnit.instantiate(with:description,options:[])
        engine.attach(mixer)
        engine.connect(engine.inputNode,to:mixer,format:source)
        engine.connect(mixer,to:engine.mainMixerNode,format:stereo)
        mixer.installTap(onBus:0,bufferSize:512,format:stereo) { buffer,_ in stats.receive(buffer) }
        engine.mainMixerNode.outputVolume = 0
        engine.prepare(); try engine.start() // Matrix volume parameters require initialised resources.
        let unit = mixer.audioUnit
        func set(_ scope: AudioUnitScope, _ element: AudioUnitElement, _ value: Float, parameter: AudioUnitParameterID = kMatrixMixerParam_Volume) throws {
            let result = AudioUnitSetParameter(unit,parameter,scope,element,value,0)
            guard result == noErr else { throw AudioMonitor.MonitorError.route("Audio channel mapping failed (\(result)).") }
        }
        try set(kAudioUnitScope_Input,0,1,parameter:kMatrixMixerParam_Enable)
        try set(kAudioUnitScope_Output,0,1,parameter:kMatrixMixerParam_Enable)
        for channel in 0..<Int(source.channelCount) {
            let selected = channel >= inputOffset && channel < inputOffset + (dry ? 4 : 2)
            try set(kAudioUnitScope_Input,UInt32(channel),selected ? 1 : 0)
            for output in 0..<2 {
                let volume: Float = dry ? (selected ? 0.25 : 0) : (channel == inputOffset+output ? 1 : 0)
                try set(kAudioUnitScope_Global,UInt32((channel << 16)|output),volume)
            }
        }
        for output in 0..<2 { try set(kAudioUnitScope_Output,UInt32(output),1) }
        try set(kAudioUnitScope_Global,0xFFFFFFFF,1)
    }
}
