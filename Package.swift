// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "FluxRelay",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "FluxRelay", targets: ["FluxRelay"])
  ],
  targets: [
    .executableTarget(
      name: "FluxRelay",
      path: "Sources/FluxRelay"
    ),
    .testTarget(
      name: "FluxRelayTests",
      dependencies: ["FluxRelay"]
    )
  ]
)
