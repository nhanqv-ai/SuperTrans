// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SuperTrans",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "SuperTransCore",
            targets: ["SuperTransCore"]
        ),
        .executable(
            name: "SuperTrans",
            targets: ["SuperTrans"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SuperTransCore",
            dependencies: [],
            path: "Sources/SuperTransCore"
        ),
        .executableTarget(
            name: "SuperTrans",
            dependencies: ["SuperTransCore"],
            path: "Sources/SuperTrans"
        ),
        .testTarget(
            name: "SuperTransTests",
            dependencies: ["SuperTransCore", "SuperTrans"],
            path: "Tests/SuperTransTests"
        )
    ]
)
