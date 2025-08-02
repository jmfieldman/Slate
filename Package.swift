// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Slate",
    platforms: [.iOS(.v17), .macOS(.v12), .tvOS(.v17), .watchOS(.v6)],

    // MARK: - Products

    products: [
        // MARK: Executables

        /** Generates slate files from a Core Data xcdatamodel file */
        .executable(name: "slategen", targets: ["SlateGenerator"]),

        // MARK: Libraries

        /** The actual Slate library */
        .library(name: "Slate", targets: ["Slate"]),
    ],

    // MARK: - Dependencies

    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.6.1"),
    ],

    // MARK: - Targets

    targets: [
        // MARK: Executables

        .executableTarget(
            name: "SlateGenerator",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "SlateGeneratorLib",
            ],
            path: "SlateGenerator/Command"
        ),

        // MARK: Libraries

        .target(
            name: "Slate",
            dependencies: [],
            path: "Slate"
        ),

        .target(
            name: "SlateGeneratorLib",
            dependencies: [],
            path: "SlateGenerator/Library"
        ),

        // MARK: Tests

        .testTarget(
            name: "SlateTests",
            dependencies: [
                "Slate",
                "DatabaseModels",
                "ImmutableModels",
            ],
            path: "Tests/SlateTests"
        ),

        .target(
            name: "DatabaseModels",
            dependencies: [
                "ImmutableModels",
                "Slate",
            ],
            path: "Tests/Generated/DatabaseModels"
        ),
        .target(
            name: "ImmutableModels",
            dependencies: [
                "Slate",
            ],
            path: "Tests/Generated/ImmutableModels"
        ),
    ]
)
