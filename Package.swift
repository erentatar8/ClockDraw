// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClockDraw",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "ClockDraw", path: "Sources/ClockDraw")
    ]
)
