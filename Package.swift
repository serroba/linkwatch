// swift-tools-version: 6.1
import PackageDescription

let strictSettings: [SwiftSetting] = [
  .enableUpcomingFeature("ExistentialAny"),
  .enableUpcomingFeature("InternalImportsByDefault"),
  .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
  name: "LinkWatch",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "LinkWatchCore", targets: ["LinkWatchCore"]),
    .library(name: "LinkWatchNetworking", targets: ["LinkWatchNetworking"]),
    .executable(name: "LinkWatch", targets: ["LinkWatchApp"]),
  ],
  targets: [
    .target(name: "LinkWatchCore", swiftSettings: strictSettings),
    .target(
      name: "LinkWatchNetworking", dependencies: ["LinkWatchCore"], swiftSettings: strictSettings),
    .executableTarget(
      name: "LinkWatchApp", dependencies: ["LinkWatchCore", "LinkWatchNetworking"],
      swiftSettings: strictSettings),
    .testTarget(
      name: "LinkWatchCoreTests", dependencies: ["LinkWatchCore"], swiftSettings: strictSettings),
    .testTarget(
      name: "LinkWatchNetworkingTests", dependencies: ["LinkWatchCore", "LinkWatchNetworking"],
      swiftSettings: strictSettings),
  ]
)
