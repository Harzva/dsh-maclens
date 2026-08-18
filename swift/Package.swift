// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MaclensBridge",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "MaclensBridge",
            path: "Sources/MaclensBridge"
        )
    ]
)
