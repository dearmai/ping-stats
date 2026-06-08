// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "PingStats",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PingStats", targets: ["PingStats"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "PingStats",
            path: "Sources/PingStats"
        )
    ]
)
