// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AIUsageMonitor",
    platforms: [.macOS(.v14)],
    targets: [
        // Probing and normalization: no AppKit, so it is unit-testable without a UI.
        .target(
            name: "UsageCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // The menu bar shell. Thin by design: read state, draw text, nothing else.
        .executableTarget(
            name: "AIUsageMonitor",
            dependencies: ["UsageCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "UsageCoreTests",
            dependencies: ["UsageCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
