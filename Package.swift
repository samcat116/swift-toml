// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "Toml",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6),
        .macCatalyst(.v13)
    ],
    products: [
        .library(
            name: "Toml",
            targets: ["Toml"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.12.0"),
    ],
    targets: [
        .target(
            name: "Toml",
            dependencies: [],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]),
        .testTarget(
            name: "TomlTests",
            dependencies: [
                "Toml",
                .product(name: "Testing", package: "swift-testing")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]),
        ]
)
