// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VJCocteau",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "VJCocteau",
            path: "Sources/VJCocteau",
            resources: [.copy("Shaders")]
        )
    ]
)
