// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "DYSQL",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DYSQL", targets: ["DYSQL"]),
        .executable(name: "dy-sql-bench", targets: ["dy-sql-bench"]),
    ],
    dependencies: [.package(path: "../DYCore")],
    targets: [
        .target(name: "DYSQL", dependencies: ["DYCore"], swiftSettings: [.swiftLanguageMode(.v5)],
                linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(name: "dy-sql-bench", dependencies: ["DYSQL", "DYCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "DYSQLTests", dependencies: ["DYSQL", "DYCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
