// swift-tools-version:6.4

import PackageDescription

let package = Package(
    name: "SwiftAE",
    platforms: [.macOS(.v13)],
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
            exclude: ["main.swift"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .target(
            name: "MacOSGlues",
            dependencies: ["SwiftAutomation"],
            path: "MacOSGlues",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
