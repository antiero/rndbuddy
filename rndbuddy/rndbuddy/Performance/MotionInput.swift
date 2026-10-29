import Foundation
import Observation
#if os(iOS)
import CoreMotion
#endif

@MainActor @Observable final class MotionInput: PerformanceInputSource {
    var onContacts: (([Contact]) -> Void)?
    private(set) var running = false
    private(set) var available = false
    private var task: Task<Void, Never>?
    private var origin: (Double, Double)?
    #if os(iOS)
    private let manager = CMMotionManager()
    #endif
    init() {
        #if os(iOS)
        available = manager.isDeviceMotionAvailable
        #endif
    }
    func start() {
        #if os(iOS)
        guard available, !running else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60
        manager.startDeviceMotionUpdates(); running = true; origin = nil
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if let attitude = self.manager.deviceMotion?.attitude {
                    let pitch = attitude.pitch, roll = attitude.roll
                    if self.origin == nil { self.origin = (pitch,roll) }
                    if let origin = self.origin {
                        self.onContacts?([Contact(id: "motion", x: (0.5 + (roll-origin.1) / 1.4).clamped(0...1), y: (0.5 + (pitch-origin.0) / 1.4).clamped(0...1))])
                    }
                }
                try? await Task.sleep(for: .milliseconds(17))
            }
        }
        #endif
    }
    func calibrate() { origin = nil }
    func stop() {
        task?.cancel(); task = nil; running = false; origin = nil
        #if os(iOS)
        manager.stopDeviceMotionUpdates()
        #endif
        onContacts?([])
    }
}
