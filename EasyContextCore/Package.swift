// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EasyContextCore",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "EasyContextCore", targets: ["EasyContextCore"]),
    ],
    targets: [
        .target(name: "EasyContextCore", resources: [.process("Localizable.xcstrings")]),
        .testTarget(name: "EasyContextCoreTests", dependencies: ["EasyContextCore"]),
    ]
)
