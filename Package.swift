// swift-tools-version: 6.0

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "Slate",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .watchOS(.v10),
    ],
    products: [
        .library(name: "Slate", targets: ["Slate"]),
        .library(name: "SlateSchema", targets: ["SlateSchema"]),
        .executable(name: "slate-generator", targets: ["SlateGenerator"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-syntax.git", exact: "603.0.0"),
    ],
    targets: [
        .target(
            name: "Slate",
            dependencies: ["SlateSchema"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .target(
            name: "SlateSchema",
            dependencies: ["SlateSchemaMacros"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .macro(
            name: "SlateSchemaMacros",
            dependencies: [
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "SlateGeneratorLib",
            dependencies: [
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .executableTarget(
            name: "SlateGenerator",
            dependencies: [
                "SlateGeneratorLib",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "SlateTests",
            dependencies: [
                "Slate",
                "SlateFixturePatientModels",
                "SlateFixturePatientPersistence",
            ]
        ),
        .testTarget(
            name: "SlateSchemaMacroTests",
            dependencies: [
                "SlateSchemaMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
        .testTarget(
            name: "SlateGeneratorTests",
            dependencies: [
                "SlateGeneratorLib",
                "SlateFixturePatientModels",
                "SlateFixturePatientPersistence",
            ]
        ),
        .target(
            name: "SlateFixturePatientModels",
            dependencies: ["SlateSchema"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .target(
            name: "SlateFixturePatientPersistence",
            dependencies: [
                "Slate",
                "SlateSchema",
                "SlateFixturePatientModels",
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
    ]
)
