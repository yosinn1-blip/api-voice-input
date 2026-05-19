// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "APIVoiceInput",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "APIVoiceInputCore", targets: ["APIVoiceInputCore"]),
        .executable(name: "APIVoiceInputApp", targets: ["APIVoiceInputApp"])
    ],
    targets: [
        .target(
            name: "APIVoiceInputCore",
            dependencies: [],
            linkerSettings: [
                .linkedFramework("Security"),
                .linkedFramework("AVFoundation")
            ]
        ),
        .executableTarget(
            name: "APIVoiceInputApp",
            dependencies: ["APIVoiceInputCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("Security"),
                .linkedFramework("CoreGraphics")
            ]
        ),
        .testTarget(
            name: "APIVoiceInputCoreTests",
            dependencies: ["APIVoiceInputCore"]
        )
    ]
)
