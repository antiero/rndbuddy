// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MIDIVisionHandTrackingCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "MIDIVisionHandTrackingCore",
            targets: ["MIDIVisionHandTrackingCore"]
        )
    ],
    targets: [
        .target(
            name: "MIDIVisionHandTrackingCore"
        ),
        .testTarget(
            name: "MIDIVisionHandTrackingCoreTests",
            dependencies: ["MIDIVisionHandTrackingCore"]
        )
    ]
)
