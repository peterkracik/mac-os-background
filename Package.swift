// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "descreet",
    platforms: [.macOS("14.0")],
    targets: [
        .executableTarget(
            name: "descreet",
            path: "Sources/descreet",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
