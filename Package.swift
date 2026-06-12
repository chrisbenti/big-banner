// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "banner",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "big-banner", path: "Sources/big-banner")
    ]
)
