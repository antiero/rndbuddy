import CoreGraphics
import Vision

public enum HandSkeletonLayout {
    public static let boneChains: [[VNHumanHandPoseObservation.JointName]] = [
        [.wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip],
        [.wrist, .indexMCP, .indexPIP, .indexDIP, .indexTip],
        [.wrist, .middleMCP, .middlePIP, .middleDIP, .middleTip],
        [.wrist, .ringMCP, .ringPIP, .ringDIP, .ringTip],
        [.wrist, .littleMCP, .littlePIP, .littleDIP, .littleTip],
    ]

    public static let fingertipJoints: [VNHumanHandPoseObservation.JointName] = [
        .thumbTip, .indexTip, .middleTip, .ringTip, .littleTip
    ]

    public static func palmCenter(from points: [VNHumanHandPoseObservation.JointName: CGPoint]) -> CGPoint? {
        let anchors: [VNHumanHandPoseObservation.JointName] = [
            .wrist, .thumbCMC, .indexMCP, .middleMCP, .ringMCP, .littleMCP
        ]
        let available = anchors.compactMap { points[$0] }
        guard available.count >= 2 else { return nil }

        let sum = available.reduce(CGPoint.zero) { partial, point in
            CGPoint(x: partial.x + point.x, y: partial.y + point.y)
        }

        return CGPoint(
            x: sum.x / CGFloat(available.count),
            y: sum.y / CGFloat(available.count)
        )
    }
}

public struct AspectFillPointMapper {
    private let frameSize: CGSize
    private let viewSize: CGSize
    private let normalizePoint: (CGPoint) -> CGPoint

    public init(frameSize: CGSize,
                viewSize: CGSize,
                normalizePoint: @escaping (CGPoint) -> CGPoint) {
        self.frameSize = frameSize
        self.viewSize = viewSize
        self.normalizePoint = normalizePoint
    }

    public func map(_ normalizedPoint: CGPoint) -> CGPoint {
        guard frameSize.width > 0,
              frameSize.height > 0,
              viewSize.width > 0,
              viewSize.height > 0 else {
            return .zero
        }

        let normalized = normalizePoint(normalizedPoint)
        let scale = max(viewSize.width / frameSize.width, viewSize.height / frameSize.height)
        let drawnWidth = frameSize.width * scale
        let drawnHeight = frameSize.height * scale
        let offsetX = (viewSize.width - drawnWidth) * 0.5
        let offsetY = (viewSize.height - drawnHeight) * 0.5

        return CGPoint(
            x: normalized.x * frameSize.width * scale + offsetX,
            y: (1.0 - normalized.y) * frameSize.height * scale + offsetY
        )
    }
}
