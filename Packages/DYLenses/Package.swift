// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "DYLenses",
    platforms: [.macOS(.v15)],
    products: [.library(name: "DYLenses", targets: ["DYLenses"])],
    dependencies: [
        .package(path: "../DYCore"),
        .package(path: "../DYAnalysis"),
        .package(path: "../DYAdvisor"),
        .package(path: "../DYDecide"),
        .package(path: "../DYPreview"),
        .package(path: "../DYWorkspace"),
    ],
    targets: [
        .target(
            name: "DYLenses",
            dependencies: ["DYCore", "DYAnalysis", "DYAdvisor", "DYDecide", "DYPreview", "DYWorkspace"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "DYLensesTests", dependencies: ["DYLenses", "DYCore", "DYAnalysis", "DYAdvisor", "DYPreview", "DYWorkspace"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
