// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MotionSystem",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "MotionCore", targets: ["MotionCore"]),
        .library(name: "MotionSwiftUI", targets: ["MotionSwiftUI"]),
        .library(name: "MotionStudio", targets: ["MotionStudio"])
    ],
    targets: [
        .target(name: "MotionCore"),
        .target(name: "MotionSwiftUI", dependencies: ["MotionCore"]),
        .target(name: "MotionStudio", dependencies: ["MotionCore", "MotionSwiftUI"])
    ]
)
