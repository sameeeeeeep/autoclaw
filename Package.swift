// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Autoclaw",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.12.0"),
    ],
    targets: [
        .executableTarget(
            name: "Autoclaw",
            dependencies: ["WhisperKit"],
            path: "Sources",
            resources: [
                .copy("../Resources"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Speech"),
                .linkedFramework("Vision"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("NaturalLanguage"),
                .linkedFramework("CoreML"),
            ]
        ),
        .executableTarget(
            name: "WhisperTest",
            dependencies: ["WhisperKit"],
            path: "Tests"
        ),
    ]
)
