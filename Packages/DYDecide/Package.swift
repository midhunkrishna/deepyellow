// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "DYDecide",
    platforms: [.macOS(.v15)],
    products: [.library(name: "DYDecide", targets: ["DYDecide"])],
    dependencies: [.package(path: "../DYCore")],
    targets: [
        .target(name: "DYDecide", dependencies: [.product(name: "DYCore", package: "DYCore")],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "DYDecideTests", dependencies: ["DYDecide", .product(name: "DYCore", package: "DYCore")],
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
