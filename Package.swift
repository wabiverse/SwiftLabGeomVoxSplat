// swift-tools-version: 6.1
import PackageDescription

let package = Package(
  name: "SwiftLabGeomVoxSplat",
  platforms: [
    .macOS(.v15),
    .visionOS(.v1),
    .iOS(.v18),
    .tvOS(.v18)
  ],
  products: [
    .library(name: "LabGeomVoxSplat", targets: ["LabGeomVoxSplat"]),
    .library(name: "VoxSplat", targets: ["VoxSplat"]),
  ],
  targets: [
    .target(
      name: "LabGeomVoxSplat",
      path: ".",
      sources: [
        "LabGeomVoxSplat/src/qef.cpp",
        "LabGeomVoxSplat/src/sampler.cpp",
        "LabGeomVoxSplat/src/splat/splat_loader.cpp",
      ],
      publicHeadersPath: "Sources/LabGeomVoxSplat/include",
      cxxSettings: [
        .headerSearchPath("LabGeomVoxSplat/include"),
        .headerSearchPath("LabGeomVoxSplat/third_party"),
      ]
    ),

    .target(
      name: "VoxSplat",
      dependencies: [
        .target(name: "LabGeomVoxSplat"),
      ],
      swiftSettings: [
        .interoperabilityMode(.Cxx)
      ]
    ),

    .testTarget(
      name: "VoxSplatTests",
      dependencies: [
        .target(name: "VoxSplat"),
      ],
      swiftSettings: [
        .interoperabilityMode(.Cxx)
      ]
    ),
  ],
  cxxLanguageStandard: .gnucxx20
)
