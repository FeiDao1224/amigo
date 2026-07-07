// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Lingzai",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Lingzai",
            path: "Sources/Lingzai"
        )
    ]
)
