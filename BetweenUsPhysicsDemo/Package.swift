// swift-tools-version: 5.9
import PackageDescription

// 这里只测试与平台无关的真实配置、几何和队列；苹果物理场景由附带工程编译。
let package = Package(
    name: "BetweenUsPhysicsCore",
    platforms: [.iOS(.v17)],
    products: [.library(name: "PhysicsCore", targets: ["PhysicsCore"])],
    targets: [
        .target(name: "PhysicsCore", path: "Sources/PhysicsCore"),
        .testTarget(name: "PhysicsCoreTests", dependencies: ["PhysicsCore"],
                    path: "Tests/PhysicsCoreTests")
    ]
)
