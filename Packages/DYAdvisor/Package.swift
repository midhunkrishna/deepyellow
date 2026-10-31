// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "DYAdvisor",
    platforms: [.macOS(.v15)],
    products: [.library(name: "DYAdvisor", targets: ["DYAdvisor"])],
    dependencies: [.package(path: "../DYCore"), .package(path: "../DYAnalysis")],
    targets: [
        .target(name: "DYAdvisor", dependencies: ["DYCore", .product(name: "DYAnalysis", package: "DYAnalysis")], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "DYAdvisorTests", dependencies: ["DYAdvisor", "DYCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
