import Foundation
import CoreMIDI
import os

struct MIDIEndpoint: Identifiable, Equatable, Sendable {
    let id: Int32
    let name: String
    let source: MIDIEndpointRef
    let destination: MIDIEndpointRef
}
struct MIDIEvent: Sendable {
    let bytes: [UInt8]
    let hostTime: UInt64
}
@MainActor protocol MIDITransport: AnyObject {
    var endpoints: [MIDIEndpoint] { get }
    var onReceive: ((MIDIEvent) -> Void)? { get set }
    var onEndpointsChanged: (() -> Void)? { get set }
    func startClock(bpm: Int) throws
    func stopClock()
    func refresh()
    func select(_ endpoint: MIDIEndpoint?)
    func send(_ bytes: [UInt8], at time: UInt64) throws
}

// MIDI's callback queue is independent of the UI. Parsing is protected by a lock;
// complete value-type events cross to the main actor, never callback-owned pointers.
private final class MIDIReceiver: Sendable {
    private struct State { var parser = MIDIStreamParser(); var epoch = 0 }
    private let state = OSAllocatedUnfairLock(initialState: State())
    let deliver: @Sendable ([MIDIEvent], Int) -> Void
    var epoch: Int { state.withLock { $0.epoch } }
    init(deliver: @escaping @Sendable ([MIDIEvent], Int) -> Void) { self.deliver = deliver }
    func reset() { state.withLock { $0.parser.reset(); $0.epoch += 1 } }
    func receive(_ list: UnsafePointer<MIDIPacketList>) {
        var events: [MIDIEvent] = []
        let epoch = self.epoch
        do {
            let first = UnsafeRawPointer(list).advanced(by: MemoryLayout<MIDIPacketList>.offset(of: \.packet)!).assumingMemoryBound(to: MIDIPacket.self)
            var packet = first
            for _ in 0..<list.pointee.numPackets {
                let data = UnsafeRawPointer(packet).advanced(by: MemoryLayout<MIDIPacket>.offset(of: \.data)!).assumingMemoryBound(to: UInt8.self)
                let bytes = Array(UnsafeBufferPointer(start: data, count: Int(packet.pointee.length)))
                let stamp = packet.pointee.timeStamp == 0 ? mach_absolute_time() : packet.pointee.timeStamp
                let messages: [[UInt8]] = state.withLock { state in
                    guard state.epoch == epoch else { return [] }
                    return state.parser.consume(bytes)
                }
                events += messages.map { MIDIEvent(bytes: $0, hostTime: stamp) }
                packet = UnsafePointer(MIDIPacketNext(packet))
            }
        }
        if !events.isEmpty { deliver(events, epoch) }
    }
}

@MainActor @Observable final class CoreMIDITransport: MIDITransport {
    private(set) var endpoints: [MIDIEndpoint] = []
    var onReceive: ((MIDIEvent) -> Void)?
    var onEndpointsChanged: (() -> Void)?
    private let clock = MIDIClockScheduler()
    private var client = MIDIClientRef()
    private var input = MIDIPortRef()
    private var output = MIDIPortRef()
    private var selected: MIDIEndpoint?
    private var receiver: MIDIReceiver?
    private(set) var error: String?

    init() {
        var result = MIDIClientCreateWithBlock("rndbuddy" as CFString, &client, Self.notificationBlock { [weak self] in self?.refresh() })
        guard result == noErr else { error = "MIDI service could not start (\(result))."; return }
        let receiver = MIDIReceiver { [weak self] events, epoch in
            Task { @MainActor in
                guard let self, self.receiver?.epoch == epoch else { return }
                for event in events { self.onReceive?(event) }
            }
        }
        self.receiver = receiver
        result = MIDIInputPortCreateWithBlock(client, "RND input" as CFString, &input, Self.readBlock(receiver:receiver))
        guard result == noErr else { error = "MIDI input could not start (\(result))."; return }
        result = MIDIOutputPortCreate(client, "RND output" as CFString, &output)
        if result != noErr { error = "MIDI output could not start (\(result))." }
        refresh()
    }
    nonisolated private static func readBlock(receiver: MIDIReceiver) -> MIDIReadBlock {
        { list, _ in receiver.receive(list) }
    }
    nonisolated private static func notificationBlock(_ action: @escaping @MainActor @Sendable () -> Void) -> MIDINotifyBlock {
        { _ in Task { @MainActor in action() } }
    }
    func refresh() {
        var found: [MIDIEndpoint] = []
        for index in 0..<MIDIGetNumberOfSources() {
            let source = MIDIGetSource(index)
            let entity = entityFor(source)
            var unique: Int32 = 0
            MIDIObjectGetIntegerProperty(source, kMIDIPropertyUniqueID, &unique)
            let name = nameFor(source)
            let destinations = (0..<MIDIGetNumberOfDestinations()).map { MIDIGetDestination($0) }
            let destination = destinations.first { entity != 0 && entityFor($0) == entity }
                ?? destinations.first { nameFor($0) == name }
            if let destination { found.append(MIDIEndpoint(id: unique, name: name, source: source, destination: destination)) }
        }
        endpoints = found
        if let old = selected {
            let replacement = found.first { $0.id == old.id }
            if replacement != old { select(replacement) }
        }
        onEndpointsChanged?()
    }
    private func entityFor(_ endpoint: MIDIEndpointRef) -> MIDIEntityRef {
        var entity = MIDIEntityRef(); MIDIEndpointGetEntity(endpoint, &entity); return entity
    }
    private func nameFor(_ object: MIDIObjectRef) -> String {
        var value: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(object, kMIDIPropertyDisplayName, &value)
        return value?.takeRetainedValue() as String? ?? "MIDI device"
    }
    func select(_ endpoint: MIDIEndpoint?) {
        stopClock()
        if let selected { MIDIPortDisconnectSource(input, selected.source) }
        receiver?.reset(); selected = endpoint
        if let endpoint {
            let status = MIDIPortConnectSource(input, endpoint.source, nil)
            if status != noErr { error = "Could not connect MIDI input (\(status))."; selected = nil }
        }
    }
    func startClock(bpm: Int) throws {
        guard let selected else { throw TransportError.disconnected }
        clock.start(port:output,destination:selected.destination,bpm:bpm)
    }
    func stopClock() { clock.stop() }
    func send(_ bytes: [UInt8], at time: UInt64 = 0) throws {
        guard let selected, output != 0 else { throw TransportError.disconnected }
        guard MIDIStreamParser.valid(bytes) else { throw TransportError.invalid }
        // One packet list per ordered chunk. SysEx framing is preserved across chunks.
        for offset in stride(from: 0, to: bytes.count, by: 256) {
            let chunk = Array(bytes[offset..<min(offset + 256, bytes.count)])
            var list = MIDIPacketList()
            let status: OSStatus = withUnsafeMutablePointer(to: &list) { pointer in
                let packet = MIDIPacketListInit(pointer)
                _ = chunk.withUnsafeBufferPointer { MIDIPacketListAdd(pointer, MemoryLayout<MIDIPacketList>.size, packet, time, chunk.count, $0.baseAddress!) }
                return MIDISend(output, selected.destination, pointer)
            }
            guard status == noErr else { throw TransportError.failed(status) }
        }
    }
    enum TransportError: LocalizedError {
        case disconnected, invalid, failed(OSStatus)
        var errorDescription: String? {
            switch self { case .disconnected: "Connect RND to send MIDI."; case .invalid: "Invalid MIDI message."; case .failed(let code): "MIDI send failed (\(code))." }
        }
    }
}
