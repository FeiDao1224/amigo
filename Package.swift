// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Amigo",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Amigo",
            path: "Sources/Amigo"
        )
    ]
)
