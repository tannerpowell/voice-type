// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "VoiceType",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "VoiceType",
            path: "Sources",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("Carbon"),
            ]
        ),
    ]
)
