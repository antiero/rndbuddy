import Foundation
@preconcurrency import AVFoundation
import Vision
import Observation
import MIDIVisionHandTrackingCore
import ImageIO
import os

// Capture and Vision stay on one serial queue. Frames are dropped under load,
// keeping latency bounded rather than enqueueing a task for every camera frame.
private final class HandFrameProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, Sendable {
    private let pinches=OSAllocatedUnfairLock(initialState:Set<String>())
    let deliver: @Sendable ([Contact], [InputSource: Double], [HandSkeleton], CGSize) -> Void
    init(deliver: @escaping @Sendable ([Contact], [InputSource: Double], [HandSkeleton], CGSize) -> Void) { self.deliver = deliver }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { deliver([], [:], [], .zero); return }
        let hands = VisionFrameDetector.detectHands(pixelBuffer: buffer, orientation: .up, mirrorX: true)
        var contacts: [Contact] = []
        var features: [InputSource: Double] = [:]
        var seen:Set<String>=[]
        for (ordinal,hand) in hands.enumerated() {
            guard let thumb = hand.joints[.thumbTip], let index = hand.joints[.indexTip],
                  let wrist = hand.joints[.wrist], let middle = hand.joints[.middleMCP],
                  let center = HandSkeletonLayout.palmCenter(from: hand.joints) else { continue }
            let palmSize = hypot(wrist.x-middle.x,wrist.y-middle.y)
            let pinch = hypot(thumb.x-index.x,thumb.y-index.y)
            let id=hand.sideHint.map { "hand-"+$0.rawValue } ?? "hand-\(ordinal)"
            guard seen.insert(id).inserted else { continue }
            let ratio=pinch/max(0.01,palmSize)
            let active=pinches.withLock { state in
                let active=ratio < (state.contains(id) ? 0.55 : 0.35)
                if active { state.insert(id) } else { state.remove(id) }; return active
            }
            if let side = hand.sideHint {
                let right = side == .right
                features[right ? .rightPalmX : .leftPalmX] = 1 - Double(center.x)
                features[right ? .rightPalmY : .leftPalmY] = Double(center.y)
                features[right ? .rightHeight : .leftHeight] = Double(center.y)
                features[right ? .rightPinch : .leftPinch] = (1 - Double(ratio)).clamped(0...1)
            }
            guard active else { continue }
            contacts.append(Contact(id: id, x: (1-Double(center.x)).clamped(0...1), y: (1-Double(center.y)).clamped(0...1)))
        }
        let currentIDs=seen
        pinches.withLock { $0.formIntersection(currentIDs) }
        deliver(contacts, features, hands, CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer)))
    }
}

@MainActor @Observable final class HandInput: PerformanceInputSource {
    var onFeatures: (([InputSource: Double]) -> Void)?
    private(set) var skeletons: [HandSkeleton] = []
    private(set) var frameSize = CGSize(width: 640, height: 480)
    var onContacts: (([Contact]) -> Void)?
    private(set) var running = false
    private(set) var error: String?
    let captureSession = AVCaptureSession()
    private var session: AVCaptureSession { captureSession }
    private let queue = DispatchQueue(label: "rndbuddy.camera", qos: .userInitiated)
    private var processor: HandFrameProcessor?
    private var watchdog: Task<Void, Never>?
    private var lastFrame = Date.distantPast
    private var generation = 0
    private var starting = false
    private(set) var portrait = true

    func start() async {
        guard !running, !starting else { return }
        starting = true; generation += 1; let token = generation
        defer { if generation == token { starting = false } }
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        guard generation == token else { return }
        guard granted else { error = "Allow camera access in System Settings to use Hands."; return }
        do {
            session.beginConfiguration()
            for input in session.inputs { session.removeInput(input) }
            for output in session.outputs { session.removeOutput(output) }
            #if os(iOS)
            let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            #else
            let camera = AVCaptureDevice.default(for: .video)
            #endif
            guard let camera else { session.commitConfiguration(); error = "No camera is available."; return }
            let input = try AVCaptureDeviceInput(device: camera)
            guard session.canAddInput(input) else { session.commitConfiguration(); error = "Camera is in use."; return }
            session.addInput(input); session.sessionPreset = .vga640x480
            let output = AVCaptureVideoDataOutput(); output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            let processor = HandFrameProcessor { [weak self] contacts, features, skeletons, size in
                Task { @MainActor in
                    guard let self, self.running, self.generation == token else { return }
                    self.lastFrame = .now; self.skeletons = skeletons; self.frameSize = size
                    self.onContacts?(contacts); self.onFeatures?(features)
                }
            }
            self.processor = processor
            output.setSampleBufferDelegate(processor, queue: queue)
            guard session.canAddOutput(output) else { session.commitConfiguration(); error = "Camera output is unavailable."; return }
            session.addOutput(output)
            if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(portrait ? 90 : 0) {
                #if os(iOS)
                connection.videoRotationAngle = portrait ? 90 : 0
                #endif
            }
            session.commitConfiguration(); running = true; error = nil
            let session = session
            queue.async { session.startRunning() }
            watchdog = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled, let self else { return }
                    if Date().timeIntervalSince(self.lastFrame) > 0.3 { self.onContacts?([]); self.onFeatures?([:]); self.skeletons = [] }
                }
            }
        } catch { session.commitConfiguration(); self.error = error.localizedDescription }
    }
    func setPortrait(_ value: Bool) {
        portrait = value
        #if os(iOS)
        if let connection = session.outputs.first?.connection(with: .video), connection.isVideoRotationAngleSupported(value ? 90 : 0) { connection.videoRotationAngle = value ? 90 : 0 }
        #endif
    }
    func stop() {
        generation += 1; starting = false; running = false; watchdog?.cancel(); watchdog = nil
        let session = session; queue.async { session.stopRunning() }
        skeletons = []; onContacts?([]); onFeatures?([:])
    }
}
