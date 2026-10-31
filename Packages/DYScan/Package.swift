// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "DYScan",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DYScan", targets: ["DYScan"]),
        .executable(name: "dy-bench", targets: ["dy-bench"]),
    ],
    dependencies: [.package(path: "../DYCore")],
    targets: [
        .target(name: "DYScan", dependencies: ["DYCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "dy-bench", dependencies: ["DYScan", "DYCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "DYScanTests", dependencies: ["DYScan", "DYCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
