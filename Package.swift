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
        // Declared as a product so that `swift build --product TomlTestDecoder`
        // links the executable; `--target` only compiles the module behind it.
        .executable(
            name: "TomlTestDecoder",
            targets: ["TomlTestDecoder"]),
    ],
    targets: [
        // Swift Testing ships with the toolchain, so no package dependencies
        // are required.
        .target(
            name: "Toml",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]),
        // Decoder for the toml-test conformance suite; see Scripts/toml-test.sh
        .executableTarget(
            name: "TomlTestDecoder",
            dependencies: ["Toml"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]),
        .testTarget(
            name: "TomlTests",
            dependencies: ["Toml"],
            exclude: ["Fixtures"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]),
        ]
)
