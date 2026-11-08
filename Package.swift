// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VJCocteau",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "VJCocteau",
            path: "Sources/VJCocteau",
            resources: [.copy("Shaders"), .copy("Effects")],
            // マイクの使用目的の説明(Info.plist)を、実行ファイルに埋め込みます。
            linkerSettings: [.unsafeFlags([
                "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
                "-Xlinker", "Sources/VJCocteau/Info.plist"])]
        )
    ]
)
