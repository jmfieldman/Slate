// swift-tools-version:5.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "Slate",
  platforms: [.iOS(.v9), .macOS(.v10_12), .tvOS(.v9), .watchOS(.v2)],

  // MARK: - Products

  products: [

    // MARK: Executables

    /** Generates slate files from a Core Data MOMD file */
    .executable(name: "slategen", targets: ["SlateGenerator"]),    

    // MARK: Libraries

    /** The actual Slate library */
    .library(name: "Slate", targets: ["Slate"]),    
  ],

  // MARK: - Dependencies

  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "0.3.1"),
    .package(url: "https://github.com/yahoojapan/SwiftyXMLParser.git", from: "5.3.0"),    
  ],

  // MARK: - Targets

  targets: [

    // MARK: Executables

    .target(
      name: "SlateGenerator",
      dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "SwiftyXMLParser", package: "SwiftyXMLParser"),
      ],
      path: "SlateGenerator/Sources"
    ),

    // MARK: Libraries

    .target(
      name: "Slate",
      dependencies: [],
      path: "Slate/Sources"
    ),
  ]
)
