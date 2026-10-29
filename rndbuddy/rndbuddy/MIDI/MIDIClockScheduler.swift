import Foundation
import CoreMIDI
import os

/// CoreMIDI clock transmission runs independently of SwiftUI/WebKit work.
/// The native transport owns the port and cancels this timer before disconnect.
@MainActor final class MIDIClockScheduler {
    private var timer: DispatchSourceTimer?
    func start(port: MIDIPortRef, destination: MIDIEndpointRef, bpm: Int) {
        stop()
        let interval = 60.0 / Double(bpm.clamped(20...400)) / 24
        let queue = DispatchQueue(label:"rndbuddy.midi-clock",qos:.userInteractive)
        let timer = DispatchSource.makeTimerSource(queue:queue)
        timer.schedule(deadline:.now(),repeating:interval,leeway:.microseconds(100))
        timer.setEventHandler {
            var list = MIDIPacketList()
            withUnsafeMutablePointer(to:&list) { pointer in
                let packet = MIDIPacketListInit(pointer)
                let data: [UInt8] = [0xF8]
                _ = data.withUnsafeBufferPointer { MIDIPacketListAdd(pointer,MemoryLayout<MIDIPacketList>.size,packet,mach_absolute_time(),1,$0.baseAddress!) }
                MIDISend(port,destination,pointer)
            }
        }
        self.timer = timer; timer.resume()
    }
    func stop() { timer?.cancel(); timer = nil }
}
