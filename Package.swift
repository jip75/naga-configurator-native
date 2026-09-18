// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NagaConfigurator",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "NagaConfigurator",
            resources: [.copy("Resources")]
        ),
        .executableTarget(
            name: "HIDSenderProbe"
        )
    ]
)
