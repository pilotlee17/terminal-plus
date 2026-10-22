// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CodexTiles",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "CodexTiles", targets: ["CodexTiles"])],
    dependencies: [.package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.99.1")],
    targets: [
        .target(name: "TilesCore"),
        .executableTarget(name: "CodexTiles", dependencies: ["TilesCore", .product(name: "SwiftTerm", package: "SwiftTerm")]),
        .testTarget(name: "TilesCoreTests", dependencies: ["TilesCore"]),
        .testTarget(name: "SessionIntegrationTests", dependencies: ["CodexTiles", "TilesCore"])
    ],
    swiftLanguageModes: [.v5]
)
