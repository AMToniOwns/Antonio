// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TripDetection",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "TripDetection", targets: ["TripDetection"])
    ],
    targets: [
        .target(name: "TripDetection"),
        .testTarget(name: "TripDetectionTests", dependencies: ["TripDetection"])
    ]
)
