// swift-tools-version: 6.1
import PackageDescription

let package = Package(
  name: "LinkWatch",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "LinkWatchCore", targets: ["LinkWatchCore"]),
    .library(name: "LinkWatchNetworking", targets: ["LinkWatchNetworking"]),
    .executable(name: "LinkWatch", targets: ["LinkWatchApp"]),
  ],
  targets: [
    .target(name: "LinkWatchCore"),
    .target(name: "LinkWatchNetworking", dependencies: ["LinkWatchCore"]),
    .executableTarget(
      name: "LinkWatchApp", dependencies: ["LinkWatchCore", "LinkWatchNetworking"]),
    .testTarget(name: "LinkWatchCoreTests", dependencies: ["LinkWatchCore"]),
    .testTarget(name: "LinkWatchNetworkingTests", dependencies: ["LinkWatchNetworking"]),
  ]
)
