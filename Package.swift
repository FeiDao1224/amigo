// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Amigo",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Amigo", targets: ["Amigo"])
    ],
    targets: [
        .target(
            name: "AmigoCore",
            path: "Sources/AmigoCore"
        ),
        .executableTarget(
            name: "Amigo",
            dependencies: ["AmigoCore"],
            path: "Sources/Amigo"
        ),
        .testTarget(
            name: "AmigoCoreTests",
            dependencies: ["AmigoCore"],
            path: "Tests/AmigoCoreTests"
        )
    ]
)
