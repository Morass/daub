// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Daub",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "DaubCore",
            path: "Sources/DaubCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Daub",
            dependencies: ["DaubCore"],
            path: "Sources/Daub",
            exclude: ["Support/Info.plist"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "DaubCoreTests",
            dependencies: ["DaubCore"],
            path: "Tests/DaubCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
