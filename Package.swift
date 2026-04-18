// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NetworkTools",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
    ],
    products: [
        .library(name: "HTMLTemplating",  targets: ["HTMLTemplating"]),
        .library(name: "NetworkClient",   targets: ["NetworkClient"]),
        .library(name: "NetworkServer",   targets: ["NetworkServer"]),
    ],
    dependencies: [
        .package(url: "https://github.com/luizmb/FP.git", exact: "1.1.2"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
    ],
    targets: [
        .target(
            name: "HTMLTemplating",
            dependencies: [
                .product(name: "FP", package: "FP"),
            ]
        ),
        .target(
            name: "NetworkClient",
            dependencies: [
                .product(name: "FP", package: "FP"),
            ]
        ),
        .target(
            name: "NetworkServer",
            dependencies: [
                .product(name: "FP",       package: "FP"),
                .product(name: "NIOCore",  package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
            ]
        ),
        .testTarget(
            name: "HTMLTemplatingTests",
            dependencies: ["HTMLTemplating"]
        ),
        .testTarget(
            name: "NetworkClientTests",
            dependencies: [
                "NetworkClient",
                .product(name: "FP", package: "FP"),
            ]
        ),
        .testTarget(
            name: "NetworkServerTests",
            dependencies: [
                "NetworkServer",
                .product(name: "NIOHTTP1", package: "swift-nio"),
            ]
        ),
    ]
)
