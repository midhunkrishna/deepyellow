// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "DYAnalysis",
    platforms: [.macOS(.v15)],
    products: [.library(name: "DYAnalysis", targets: ["DYAnalysis"])],
    dependencies: [.package(path: "../DYCore")],
    targets: [
        .target(name: "DYAnalysis", dependencies: ["DYCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "DYAnalysisTests", dependencies: ["DYAnalysis"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
