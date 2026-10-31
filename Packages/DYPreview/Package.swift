// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "DYPreview",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DYPreview", targets: ["DYPreview"]),
        .executable(name: "dy-preview-demo", targets: ["dy-preview-demo"]),
    ],
    dependencies: [.package(path: "../DYCore")],
    targets: [
        .target(name: "DYPreview", dependencies: ["DYCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "dy-preview-demo", dependencies: ["DYPreview", "DYCore"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "DYPreviewTests", dependencies: ["DYPreview", "DYCore"],
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
