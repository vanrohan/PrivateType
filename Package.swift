// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SimpleKeyboardCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "KeyboardCore", targets: ["KeyboardCore"])],
    targets: [
        .target(name: "KeyboardCore", path: "Core"),
        .testTarget(name: "KeyboardCoreTests", dependencies: ["KeyboardCore"], path: "Tests/Core")
    ]
)
