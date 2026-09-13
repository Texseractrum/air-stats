// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AirStats",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "AirStats", targets: ["AirStats"])],
    targets: [
        .target(name: "HealthCore"),
        .executableTarget(name: "AirStats", dependencies: ["HealthCore"]),
        .testTarget(name: "HealthCoreTests", dependencies: ["HealthCore"])
    ]
)
