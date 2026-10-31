// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "DYWorkspace",
    platforms: [.macOS(.v15)],
    products: [.library(name: "DYWorkspace", targets: ["DYWorkspace"])],
    dependencies: [
        .package(path: "../DYCore"), .package(path: "../DYScan"), .package(path: "../DYAnalysis"),
        .package(path: "../DYAdvisor"), .package(path: "../DYDecide"), .package(path: "../DYPreview"),
    ],
    targets: [
        .target(
            name: "DYWorkspace",
            dependencies: ["DYCore", "DYScan", "DYAnalysis", "DYAdvisor", "DYDecide", "DYPreview"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(
            name: "DYWorkspaceTests",
            dependencies: ["DYWorkspace", "DYCore", "DYScan", "DYAnalysis", "DYAdvisor", "DYDecide", "DYPreview"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
