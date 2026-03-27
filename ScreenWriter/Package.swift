// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScreenWriter",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "ScreenWriter",
            path: "Sources/ScreenWriter",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("Carbon"),
                .linkedFramework("Quartz")
            ]
        )
    ]
)
