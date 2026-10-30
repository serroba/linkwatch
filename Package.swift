// swift-tools-version: 6.1
import PackageDescription

let package = Package(
  name: "LinkWatch",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "LinkWatchCore", targets: ["LinkWatchCore"]),
    .library(name: "LinkWatchNetworking", targets: ["LinkWatchNetworking"]),
  ],
  targets: [
    .target(name: "LinkWatchCore"),
    .target(name: "LinkWatchNetworking", dependencies: ["LinkWatchCore"]),
    .testTarget(name: "LinkWatchCoreTests", dependencies: ["LinkWatchCore"]),
    .testTarget(name: "LinkWatchNetworkingTests", dependencies: ["LinkWatchNetworking"]),
  ]
)
