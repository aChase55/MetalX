// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MetalX",
    // MetalX UI relies on UIKit; keep the package iOS-only for now.
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "MetalX",
            targets: ["MetalX"]
        )
    ],
    dependencies: [
        // Async Algorithms for stream processing
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
        
        // Collections for specialized data structures
        .package(url: "https://github.com/apple/swift-collections", from: "1.0.0"),
        
        // Numerics for advanced math
        .package(url: "https://github.com/apple/swift-numerics", from: "1.0.0"),
        
        // Logging
        .package(url: "https://github.com/apple/swift-log", from: "1.5.0"),
        
        // Compression for asset management
        .package(url: "https://github.com/tsolomko/SWCompression", from: "4.8.0")
    ],
    targets: [
        // Single target that contains Core + UI code.
        // We exclude app/demo Xcode-specific files and assets not needed by SPM.
        .target(
            name: "MetalX",
            dependencies: [
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "Numerics", package: "swift-numerics"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "SWCompression", package: "SWCompression")
            ],
            path: "MetalX",
            sources: [
                // Source trees inside MetalX/MetalX
                "Core",
                "Effects",
                "Layers",
                "Models",
                "Typography",
                "UI",
                "System",
                "Util",
                "Views"
            ],
            // Let SwiftPM process shaders as resources so the compiled
            // .metallib is embedded in the package bundle (Bundle.module).
            resources: [
                .process("Shaders")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug)),
                .define("METAL_VALIDATION", .when(configuration: .debug))
            ]
        )
    ]
)
