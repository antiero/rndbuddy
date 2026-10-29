#if os(macOS)
import CoreAudio
import Foundation

struct AudioDeviceChoice: Identifiable {
    let id: AudioDeviceID
    let name: String
    static var defaultOutput: AudioDeviceID {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: AudioDeviceID = 0; var size = UInt32(MemoryLayout.size(ofValue: value))
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &value)
        return value
    }
    static func text(_ id: AudioDeviceID, selector: AudioObjectPropertySelector) -> String {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?; var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let result = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
        return result == noErr ? (value?.takeUnretainedValue() as String? ?? "") : ""
    }
    static func channels(_ id: AudioDeviceID, input: Bool) -> Int {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let memory = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { memory.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, memory) == noErr else { return 0 }
        return UnsafeMutableAudioBufferListPointer(memory.assumingMemoryBound(to: AudioBufferList.self)).reduce(0) { $0 + Int($1.mNumberChannels) }
    }
    static func available(input: Bool) -> [Self] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        let result = devices.withUnsafeMutableBytes { AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, $0.baseAddress!) }
        guard result == noErr else { return [] }
        return devices.filter { channels($0, input: input) > 0 }.map { Self(id: $0, name: text($0, selector: kAudioObjectPropertyName)) }
    }
    static func makeAggregate(input: AudioDeviceID, output: AudioDeviceID) throws -> AudioDeviceID {
        let inputUID = text(input, selector: kAudioDevicePropertyDeviceUID)
        let outputUID = text(output, selector: kAudioDevicePropertyDeviceUID)
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "rndbuddy monitoring",
            kAudioAggregateDeviceUIDKey: "rndbuddy.monitor.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID],
                [kAudioSubDeviceUIDKey: inputUID, kAudioSubDeviceDriftCompensationKey: 1]
            ]
        ]
        var device: AudioDeviceID = 0
        let result = AudioHardwareCreateAggregateDevice(description as CFDictionary, &device)
        guard result == noErr else { throw AudioMonitor.MonitorError.route("Could not create a monitoring route (\(result)).") }
        return device
    }
}
#endif
