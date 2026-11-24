// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "agentBar",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "agentBar", targets: ["agentBar"])
    ],
    targets: [
        .executableTarget(
            name: "agentBar",
            path: "Sources/agentBar",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "agentBarTests",
            dependencies: ["agentBar"],
            path: "Tests/agentBarTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
