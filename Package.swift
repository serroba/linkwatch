// swift-tools-version: 6.1
import PackageDescription

let package = Package(
  name: "LinkWatch",
  platforms: [.macOS(.v14)],
  products: [.library(name: "LinkWatchCore", targets: ["LinkWatchCore"])],
  targets: [
    .target(name: "LinkWatchCore"),
    .testTarget(name: "LinkWatchCoreTests", dependencies: ["LinkWatchCore"]),
  ]
)
