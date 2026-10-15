// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RepasoCore",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [.library(name: "RepasoCore", targets: ["RepasoCore"])],
    targets: [
        .target(name: "RepasoCore"),
        .testTarget(name: "RepasoCoreTests", dependencies: ["RepasoCore"]),
    ]
)
