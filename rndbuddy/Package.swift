// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "RNDBuddyCore", platforms: [.macOS(.v15), .iOS(.v18)], products: [.library(name: "RNDBuddyCore", targets: ["RNDBuddyCore"])], targets: [.target(name: "RNDBuddyCore", path: "rndbuddy/Core"), .testTarget(name: "RNDBuddyCoreTests", dependencies: ["RNDBuddyCore"], path: "Tests/RNDBuddyCoreTests")])
