// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Strange",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "StrangeCore", targets: ["StrangeCore"]),
        .library(name: "StrangeMac", targets: ["StrangeMac"]),
        .executable(name: "strange", targets: ["strange"]),
        .executable(name: "strange-app", targets: ["StrangeApp"])
    ],
    targets: [
        .target(name: "StrangeCore"),
        .target(name: "StrangeMac", dependencies: ["StrangeCore"]),
        .executableTarget(name: "strange", dependencies: ["StrangeMac", "StrangeCore"]),
        .executableTarget(name: "StrangeApp", dependencies: ["StrangeMac", "StrangeCore"]),
        .testTarget(name: "StrangeCoreTests", dependencies: ["StrangeCore"]),
        .testTarget(name: "StrangeMacTests", dependencies: ["StrangeMac", "StrangeCore"])
    ]
)
