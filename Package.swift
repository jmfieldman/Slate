// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "Slate",
  platforms: [.iOS(.v10), .macOS(.v10_12), .tvOS(.v10), .watchOS(.v3)],

  // MARK: - Products

  products: [

    // MARK: Executables

    /** Generates slate files from a Core Data xcdatamodel file */
    .executable(name: "slategen", targets: ["SlateGenerator"]),

    /** Setup unit tests */
    .executable(name: "test_setup", targets: ["TestSetup"]),

    // MARK: Libraries

    /** The actual Slate library */
    .library(name: "Slate", targets: ["Slate"]),

    /** The distributable components of the slate generator */
    .library(name: "SlateGeneratorLib", targets: ["SlateGeneratorLib"])
  ],

  // MARK: - Dependencies

  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "0.3.1"),
  ],

  // MARK: - Targets

  targets: [

    // MARK: Executables

    .target(
      name: "SlateGenerator",
      dependencies: [
        "SlateGeneratorLib",
      ],
      path: "SlateGenerator/Executable"
    ),

    .target(
      name: "TestSetup",
      path: "Tests/Setup"
    ),

    // MARK: Libraries

    .target(
      name: "Slate",
      dependencies: [],
      path: "Slate"
    ),

    .target(
      name: "SlateGeneratorLib",
      dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      path: "SlateGenerator/Library"
    ),

    // MARK: Tests

    .testTarget(
      name: "SlateTests",
      dependencies: ["SlateGenerator", "Slate"],
      path: "Tests/SlateTests"
    ),
  ]
)
