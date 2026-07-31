// swift-tools-version:6.3

import PackageDescription

let package = Package(
    name: "Toml",
    // A TOML parser has no platform-specific code and no OS API floor of its
    // own — these exist only so the package builds. Keep them no higher than
    // consumers need: the macOS floor is what pins the graph, and raising it
    // past a consumer's own floor makes the package unlinkable there ("requires
    // minimum platform version 26.0 ... but this target supports 15.0"), which
    // is exactly what the .v26 floor did. The other Apple platforms track the
    // same OS generation.
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .tvOS(.v18),
        .watchOS(.v11),
        .macCatalyst(.v18)
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
