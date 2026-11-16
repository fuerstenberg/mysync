// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MySyncCore",
    defaultLocalization: "de",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MySyncCore", targets: ["MySyncCore"])
    ],
    targets: [
        .target(
            name: "MySyncCore",
            path: "Sources/MySyncCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MySyncCoreTests",
            dependencies: ["MySyncCore"],
            path: "Tests/MySyncCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
