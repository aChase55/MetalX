// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MetalX",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "MetalX",
            targets: ["MetalX"]
        ),
        .library(
            name: "MetalXUI",
            targets: ["MetalXUI"]
        )
    ],
    dependencies: [
        // Core ML Models (for style transfer, segmentation, etc.)
        .package(url: "https://github.com/apple/ml-stable-diffusion", from: "1.0.0"),
        
        // Async Algorithms for stream processing
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
        
        // Collections for specialized data structures
        .package(url: "https://github.com/apple/swift-collections", from: "1.0.0"),
        
        // Numerics for advanced math
        .package(url: "https://github.com/apple/swift-numerics", from: "1.0.0"),
        
        // Logging
        .package(url: "https://github.com/apple/swift-log", from: "1.5.0"),
        
        // Compression for asset management
        .package(url: "https://github.com/tsolomko/SWCompression", from: "4.8.0"),
        
        // Testing tools
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.15.0"),
        
        // Benchmarking
        .package(url: "https://github.com/apple/swift-benchmark", from: "0.1.2")
    ],
    targets: [
        .target(
            name: "MetalX",
            dependencies: [
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "Numerics", package: "swift-numerics"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "SWCompression", package: "SWCompression")
            ],
            resources: [
                .process("Shaders"),
                .process("Models"),
                .process("Resources")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug)),
                .define("METAL_VALIDATION", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "MetalXUI",
            dependencies: ["MetalX"],
            resources: [
                .process("Assets")
            ]
        ),
        .testTarget(
            name: "MetalXTests",
            dependencies: [
                "MetalX",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
                .product(name: "Benchmark", package: "swift-benchmark")
            ],
            resources: [
                .process("TestResources"),
                .process("ReferenceImages")
            ]
        )
    ]
)

// Development dependencies (not included in release)
#if os(macOS)
package.dependencies.append(
    .package(url: "https://github.com/apple/swift-format", from: "509.0.0")
)
#endif