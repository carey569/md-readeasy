// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ReadEasy",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ReadEasy",
            path: "Sources/ReadEasy",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
