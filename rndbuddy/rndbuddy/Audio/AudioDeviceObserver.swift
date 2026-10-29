#if os(macOS)
import CoreAudio
import Foundation

/// Owns the HAL registration so short-lived presentation models leave no
/// orphaned device-list callbacks behind.
final class AudioDeviceObserver {
    private let listener: AudioObjectPropertyListenerBlock
    init(onChange: @escaping @Sendable () -> Void) {
        listener = { _, _ in onChange() }
        var address = Self.address
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
    }
    deinit {
        var address = Self.address
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
    }
    private static var address: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
}
#endif
