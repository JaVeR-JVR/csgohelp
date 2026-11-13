// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CSGOHelper",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "CSGOHelperCore", targets: ["CSGOHelperCore"]),
        .executable(name: "csgo-helper", targets: ["CSGOHelperCLI"])
    ],
    targets: [
        .target(
            name: "CSGOHelperCore",
            path: "Sources/CSGOHelperCore"
        ),
        .executableTarget(
            name: "CSGOHelperCLI",
            dependencies: ["CSGOHelperCore"],
            path: "Sources/CSGOHelper"
        ),
        .testTarget(
            name: "CSGOHelperCoreTests",
            dependencies: ["CSGOHelperCore"],
            path: "Tests/CSGOHelperCoreTests"
        )
    ]
)
