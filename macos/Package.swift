// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "alPoolMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "alPool", targets: ["alPoolApp"]),
    ],
    targets: [
        .target(name: "alPoolCore"),
        .executableTarget(name: "alPoolApp", dependencies: ["alPoolCore"]),
        .testTarget(name: "alPoolCoreTests", dependencies: ["alPoolCore"]),
    ]
)
