// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RateEngine",
    platforms: [.iOS("18.0"), .macOS("14.0")],
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
