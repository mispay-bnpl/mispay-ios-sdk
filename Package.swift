// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "mispaysdk",
    platforms: [
        // CryptoKit (AES.GCM / HMAC) requires iOS 13 / macOS 10.15.
        .iOS(.v13),
        .macOS(.v10_15),
    ],
    products: [
        .library(
            name: "mispaysdk",
            targets: ["mispaysdk"]),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "mispaysdk"),
        .testTarget(
            name: "mispaysdkTests",
            dependencies: ["mispaysdk"]),
    ]
)
