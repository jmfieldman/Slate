// swift-tools-version:5.0
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

    // MARK: Libraries

    /** The actual Slate library */
    .library(name: "Slate", targets: ["Slate"]),    
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
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      path: "SlateGenerator"
    ),

    // MARK: Libraries

    .target(
      name: "Slate",
      dependencies: [],
      path: "Slate"
    ),

    // MARK: Tests

    .testTarget(
      name: "SlateGeneratorTests",
      dependencies: ["SlateGenerator"],
      path: "Tests/GenerationTests"
    )
  ]
)
