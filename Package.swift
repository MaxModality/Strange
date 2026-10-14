// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Strange",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "StrangeCore", targets: ["StrangeCore"])
    ],
    targets: [
        .target(name: "StrangeCore"),
        .testTarget(name: "StrangeCoreTests", dependencies: ["StrangeCore"])
    ]
)
