// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PiliPlaybackCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "PiliPlaybackCore", targets: ["PiliPlaybackCore"])],
    targets: [
        .target(name: "PiliPlaybackCore"),
        .testTarget(name: "PiliPlaybackCoreTests", dependencies: ["PiliPlaybackCore"]),
    ]
)
