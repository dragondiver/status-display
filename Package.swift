// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "StatusDisplay",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "StatusCore",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .executableTarget(name: "StatusDisplay", dependencies: ["StatusCore"]),
        .testTarget(name: "StatusCoreTests", dependencies: ["StatusCore"]),
    ],
    swiftLanguageModes: [.v5]
)
