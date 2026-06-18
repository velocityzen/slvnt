// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "slvnt",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Slvnt", targets: ["Slvnt"]),
        .executable(name: "slvnt", targets: ["SlvntCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/velocityzen/fp-swift", from: "3.3.0"),
        .package(url: "https://github.com/velocityzen/fp-swift-pipe", branch: "main"),
        .package(url: "https://github.com/velocityzen/fp-swift-bracket", branch: "main"),
    ],
    targets: [
        // Reusable library — no @main, Result-based API.
        .target(
            name: "Slvnt",
            dependencies: [
                .product(name: "FP", package: "fp-swift"),
                .product(name: "FPPipe", package: "fp-swift-pipe"),
                .product(name: "FPBracket", package: "fp-swift-bracket"),
            ],
            path: "Sources/Slvnt"
        ),
        // CLI front-end — parses args, calls into the library. Named SlvntCLI so the
        // target name does not collide with `Slvnt` on case-insensitive filesystems;
        // the built binary is `slvnt` (see products above).
        .executableTarget(
            name: "SlvntCLI",
            dependencies: [
                "Slvnt",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "FPPipe", package: "fp-swift-pipe"),
            ],
            path: "Sources/cli"
        ),
        .testTarget(
            name: "SlvntTests",
            dependencies: [
                "Slvnt",
                .product(name: "FP", package: "fp-swift"),
            ],
            path: "Tests/SlvntTests"
        ),
    ]
)
