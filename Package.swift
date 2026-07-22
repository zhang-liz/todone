// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Todone",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "TodoneKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Todone",
            dependencies: ["TodoneKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "TodoneKitTests",
            dependencies: ["TodoneKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
