import Foundation
import Observation

/// Deterministic integration seam. Fake endpoints never reach CoreMIDI.
@MainActor @Observable final class FakeMIDITransport: MIDITransport {
    var endpoints: [MIDIEndpoint] = []
    var onReceive: ((MIDIEvent) -> Void)?
    var onEndpointsChanged: (() -> Void)?
    private(set) var sent: [MIDIEvent] = []
    private(set) var selected: MIDIEndpoint?
    func startClock(bpm: Int) throws {}
    func stopClock() {}
    func refresh() { onEndpointsChanged?() }
    func select(_ endpoint: MIDIEndpoint?) { selected = endpoint }
    func send(_ bytes: [UInt8], at time: UInt64) throws {
        guard MIDIStreamParser.valid(bytes) else { throw CoreMIDITransport.TransportError.invalid }
        sent.append(MIDIEvent(bytes: bytes, hostTime: time))
    }
    func inject(_ bytes: [UInt8], at time: UInt64 = 0) { onReceive?(MIDIEvent(bytes: bytes, hostTime: time)) }
}
