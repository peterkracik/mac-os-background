// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "NoDistractions",
    platforms: [.macOS("14.0")],
    targets: [
        .executableTarget(
            name: "nodistractions",
            path: "Sources/nodistractions",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
