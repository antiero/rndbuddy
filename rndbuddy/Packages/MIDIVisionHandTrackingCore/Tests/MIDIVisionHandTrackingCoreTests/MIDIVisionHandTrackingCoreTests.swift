import CoreGraphics
import Vision
import XCTest
@testable import MIDIVisionHandTrackingCore

final class MIDIVisionHandTrackingCoreTests: XCTestCase {
    func testAspectFillPointMapperMapsCenterToCenter() {
        let mapper = AspectFillPointMapper(
            frameSize: CGSize(width: 640, height: 480),
            viewSize: CGSize(width: 1280, height: 720),
            normalizePoint: { $0 }
        )

        let mapped = mapper.map(CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(mapped.x, 640, accuracy: 0.001)
        XCTAssertEqual(mapped.y, 360, accuracy: 0.001)
    }

    func testPalmCenterUsesAvailablePalmAnchors() {
        let points: [VNHumanHandPoseObservation.JointName: CGPoint] = [
            .wrist: CGPoint(x: 0.5, y: 0.1),
            .indexMCP: CGPoint(x: 0.6, y: 0.3),
            .middleMCP: CGPoint(x: 0.5, y: 0.35),
            .ringMCP: CGPoint(x: 0.4, y: 0.3)
        ]

        let center = HandSkeletonLayout.palmCenter(from: points)
        XCTAssertNotNil(center)
        XCTAssertEqual(center?.x ?? 0, 0.5, accuracy: 0.001)
    }
}
