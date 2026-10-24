// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RateEngine",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "RateEngine", targets: ["RateEngine"])
    ],
    targets: [
        .target(
            name: "RateEngine",
            resources: [.process("Resources/rates.json")]
        ),
        .testTarget(
            name: "RateEngineTests",
            dependencies: ["RateEngine"]
        )
    ]
)
