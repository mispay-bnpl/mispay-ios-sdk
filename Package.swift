// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MISPay",
    platforms: [.iOS(.v13)],
    products: [
        .library(
            name: "MISPay",
            targets: ["MISPay"]
        ),
    ],
    targets: [
        .target(name: "MISPay")
    ]
)
