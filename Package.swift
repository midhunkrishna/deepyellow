// swift-tools-version: 6.0
import PackageDescription

// Root package: one DeepYellow executable (GUI and CLI in one binary). The code lives in the DeepYellowKit library
// so it can be tested; the executable target holds only the entry point.
let libraries = [
    "DYCore", "DYScan", "DYAnalysis", "DYAdvisor", "DYDecide", "DYRender", "DYPreview", "DYWorkspace", "DYLenses",
]
let products: [Target.Dependency] = libraries.map { .product(name: $0, package: $0) }

let package = Package(
    name: "DeepYellow",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "DeepYellow", targets: ["DeepYellow"])
    ],
    dependencies: libraries.map { .package(path: "Packages/\($0)") },
    targets: [
        .target(
            name: "DeepYellowKit",
            dependencies: products,
            path: "Sources/DeepYellow/Kit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "DeepYellow",
            dependencies: ["DeepYellowKit"],
            path: "Sources/DeepYellow/Main",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "DeepYellowKitTests",
            dependencies: ["DeepYellowKit"] + products,
            path: "Tests/DeepYellowKitTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
