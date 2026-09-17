// swift-tools-version: 5.9
import PackageDescription

// Deliberately plain: tools-version 5.9 already defaults to the Swift 5 language mode,
// and both `.swiftLanguageMode` and `swiftLanguageVersions` need manifest API that the
// Command Line Tools do not ship. This package has to build on a Mac with no Xcode.
let package = Package(
    name: "Daub",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "DaubCore",
            path: "Sources/DaubCore"
        ),
        .executableTarget(
            name: "Daub",
            dependencies: ["DaubCore"],
            path: "Sources/Daub",
            exclude: ["Support/Info.plist"]
        ),
        .testTarget(
            name: "DaubCoreTests",
            dependencies: ["DaubCore"],
            path: "Tests/DaubCoreTests"
        ),
    ]
)
