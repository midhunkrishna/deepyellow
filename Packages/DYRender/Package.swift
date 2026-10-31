// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "DYRender",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DYRender", targets: ["DYRender"]),
        .executable(name: "dy-snap", targets: ["dy-snap"]),
    ],
    dependencies: [.package(path: "../DYCore")],
    targets: [
        .target(name: "DYRender", dependencies: [.product(name: "DYCore", package: "DYCore")],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "dy-snap", dependencies: ["DYRender", .product(name: "DYCore", package: "DYCore")],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "DYRenderTests", dependencies: ["DYRender", .product(name: "DYCore", package: "DYCore")],
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
