// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AccountaBall",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "AccountaBall",
            path: "Sources/AccountaBall",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "AccountaBallApp",
            dependencies: ["AccountaBall"],
            path: "Sources/AccountaBallApp",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "AccountaBallTests",
            dependencies: ["AccountaBall"],
            path: "Tests/AccountaBallTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
