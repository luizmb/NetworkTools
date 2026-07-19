// swift-tools-version: 6.3
import PackageDescription

// ReactiveConcurrency products. `rc` = the Publisher runtime (for DeferredStream→Publisher targets);
// `rcFull` adds the transformer + operator products for targets that build `Reader<Env, Publisher>`
// pipelines (`ReaderTPublisher`), i.e. NetworkClient / NetworkServer.
let rc: [Target.Dependency] = [
    .product(name: "ReactiveConcurrency", package: "ReactiveConcurrency"),
]
let rcFull: [Target.Dependency] = rc + [
    .product(name: "ReactiveConcurrencyTransformers", package: "ReactiveConcurrency"),
    .product(name: "ReactiveConcurrencyOperators", package: "ReactiveConcurrency"),
]

let package = Package(
    name: "NetworkTools",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
    ],
    products: [
        .library(name: "Core", targets: ["Core"]),
        .library(name: "HTMLTemplating", targets: ["HTMLTemplating"]),
        .library(name: "Multipeer", targets: ["Multipeer"]),
        .library(name: "NetworkClient", targets: ["NetworkClient"]),
        .library(name: "NetworkServer", targets: ["NetworkServer"]),
        .library(name: "WebSocketClient", targets: ["WebSocketClient"]),
        .library(name: "BonjourService", targets: ["BonjourService"]),
    ],
    dependencies: [
        .package(url: "https://github.com/luizmb/FP.git", from: "2.1.0"),
        .package(url: "https://github.com/luizmb/ReactiveConcurrency.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.0"),
    ],
    targets: [
        .target(
            name: "Core",
            dependencies: [
                .product(name: "FP", package: "FP"),
            ]
        ),
        .target(
            name: "HTMLTemplating",
            dependencies: [
                .product(name: "FP", package: "FP"),
            ]
        ),
        .target(
            name: "Multipeer",
            dependencies: [
                .product(name: "FP", package: "FP"),
            ] + rc
        ),
        .target(
            name: "NetworkClient",
            dependencies: [
                "Core",
                .product(name: "FP", package: "FP"),
            ] + rcFull
        ),
        // NetworkServer is built on swift-nio (NIOPosix), which is Posix-only and does not
        // support Windows. The NIO dependencies are gated to non-Windows platforms; see the
        // platform-support matrix in README.md.
        .target(
            name: "NetworkServer",
            dependencies: [
                "Core",
                .product(name: "FP", package: "FP"),
                .product(name: "NIOCore", package: "swift-nio", condition: .when(platforms: [.macOS, .iOS, .tvOS, .watchOS, .visionOS, .linux])),
                .product(name: "NIOPosix", package: "swift-nio", condition: .when(platforms: [.macOS, .iOS, .tvOS, .watchOS, .visionOS, .linux])),
                .product(name: "NIOHTTP1", package: "swift-nio", condition: .when(platforms: [.macOS, .iOS, .tvOS, .watchOS, .visionOS, .linux])),
            ] + rcFull
        ),
        .target(
            name: "WebSocketClient",
            dependencies: [
                "Core",
                .product(name: "FP", package: "FP"),
            ] + rc
        ),
        .target(
            name: "BonjourService",
            dependencies: [
                "Core",
                .product(name: "FP", package: "FP"),
            ] + rc
        ),
        .testTarget(
            name: "HTMLTemplatingTests",
            dependencies: ["HTMLTemplating"]
        ),
        .testTarget(
            name: "MultipeerTests",
            dependencies: [
                "Multipeer",
                .product(name: "FP", package: "FP"),
            ] + rc
        ),
        .testTarget(
            name: "NetworkClientTests",
            dependencies: [
                "Core",
                "NetworkClient",
                .product(name: "FP", package: "FP"),
            ] + rcFull
        ),
        .testTarget(
            name: "NetworkServerTests",
            dependencies: [
                "Core",
                "NetworkServer",
                .product(name: "FP", package: "FP"),
                .product(name: "NIOHTTP1", package: "swift-nio", condition: .when(platforms: [.macOS, .iOS, .tvOS, .watchOS, .visionOS, .linux])),
            ] + rcFull
        ),
    ]
)
