// swift-tools-version:4.0

import PackageDescription

let package = Package(
    name: "SwiftAE",
    products: [
        .library(
            name: "SwiftAutomation",
            targets: ["SwiftAutomation"]),
        .library(
            name: "MacOSGlues",
            targets: ["MacOSGlues"]),
    ],
    targets: [
        .target(
            name: "SwiftAutomation",
            path: "SwiftAutomation",
            exclude: ["main.swift"]
        ),
        .target(
            name: "MacOSGlues",
            dependencies: ["SwiftAutomation"],
            path: "MacOSGlues"
        ),
    ]
)
