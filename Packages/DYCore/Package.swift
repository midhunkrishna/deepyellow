// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "DYCore",
    platforms: [.macOS(.v15)],
    products: [.library(name: "DYCore", targets: ["DYCore"])],
    targets: [
        .target(name: "DYCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "DYCoreTests", dependencies: ["DYCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
