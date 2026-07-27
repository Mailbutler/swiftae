// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "SwiftAE",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SwiftAutomation", targets: ["SwiftAutomation"]),
        .library(name: "MacOSGlues", targets: ["MacOSGlues"]),
    ],
    targets: [
        .target(name: "SwiftAutomation", path: "SwiftAutomation", exclude: ["main.swift"]),
        .target(name: "MacOSGlues", dependencies: ["SwiftAutomation"], path: "MacOSGlues"),
    ]
)
