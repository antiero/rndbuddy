import CoreGraphics
import Vision

public enum HandSide: String, Sendable {
    case left
    case right
}

public struct HandSkeleton: Sendable {
    public let sideHint: HandSide?
    public let wristX: CGFloat
    public let joints: [VNHumanHandPoseObservation.JointName: CGPoint]

    public init(sideHint: HandSide?,
                wristX: CGFloat,
                joints: [VNHumanHandPoseObservation.JointName: CGPoint]) {
        self.sideHint = sideHint
        self.wristX = wristX
        self.joints = joints
    }
}
