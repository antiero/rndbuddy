import CoreGraphics
import Vision

public actor VisionHandTrackingService {
    private let confidenceThreshold: Float
    private let maximumHandCount: Int
    private var isProcessing = false

    public init(confidenceThreshold: Float = 0.3,
                maximumHandCount: Int = 2) {
        self.confidenceThreshold = confidenceThreshold
        self.maximumHandCount = maximumHandCount
    }

    public func detectHands(pixelBuffer: CVPixelBuffer,
                            orientation: CGImagePropertyOrientation,
                            mirrorX: Bool) async -> [HandSkeleton]? {
        guard isProcessing == false else { return nil }
        isProcessing = true
        defer { isProcessing = false }

        return VisionFrameDetector.detectHands(pixelBuffer: pixelBuffer, orientation: orientation,
                                               mirrorX: mirrorX, confidenceThreshold: confidenceThreshold,
                                               maximumHandCount: maximumHandCount)
    }
}
