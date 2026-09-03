// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "FluxRelay",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "FluxRelay", targets: ["MotrixNative"])
  ],
  targets: [
    .executableTarget(
      name: "MotrixNative",
      path: "Sources/MotrixNative"
    ),
    .testTarget(
      name: "MotrixNativeTests",
      dependencies: ["MotrixNative"]
    )
  ]
)
