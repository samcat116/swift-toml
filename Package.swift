// swift-tools-version:6.3

import PackageDescription

let package = Package(
    name: "Toml",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
        .watchOS(.v26),
        .macCatalyst(.v26)
    ],
    products: [
        .library(
            name: "Toml",
            targets: ["Toml"]),
    ],
    targets: [
        // Swift Testing ships with the toolchain, so no package dependencies
        // are required.
        .target(
            name: "Toml",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]),
        .testTarget(
            name: "TomlTests",
            dependencies: ["Toml"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]),
        ]
)
