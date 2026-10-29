import CoreGraphics
import Vision

/// Synchronous entry point for an existing serial capture queue; no pixel buffers
/// cross concurrency domains. Adapted from MIDIVision's tracking service.
public enum VisionFrameDetector {
    public static func detectHands(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation,
                                   mirrorX: Bool, confidenceThreshold: Float = 0.4,
                                   maximumHandCount: Int = 2) -> [HandSkeleton] {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = maximumHandCount

        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: orientation,
            options: [:]
        )

        do {
            try handler.perform([request])
        } catch {
            return []
        }

        guard let observations = request.results, observations.isEmpty == false else {
            return []
        }

        var hands: [HandSkeleton] = []
        for observation in observations.prefix(maximumHandCount) {
            guard let allPoints = try? observation.recognizedPoints(.all) else { continue }

            var joints: [VNHumanHandPoseObservation.JointName: CGPoint] = [:]
            for (joint, point) in allPoints where point.confidence >= confidenceThreshold {
                joints[joint] = CGPoint(x: point.location.x, y: point.location.y)
            }
            guard let wrist = joints[.wrist] else { continue }

            let wristX = mirrorX ? (1.0 - wrist.x) : wrist.x
            hands.append(
                HandSkeleton(
                    sideHint: Self.side(from: observation),
                    wristX: wristX,
                    joints: joints
                )
            )
        }

        return hands.sorted(by: { $0.wristX < $1.wristX })
    }
    private static func side(from observation: VNHumanHandPoseObservation) -> HandSide? {
        switch observation.chirality { case .left: .left; case .right: .right; default: nil }
    }
}
