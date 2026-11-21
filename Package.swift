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

// Where swift-nio's `NIOPosix` runs: every Posix platform (Apple, Linux, Android). Windows is the
// only exclusion, so NIO-backed targets compile to empty there (sources are `#if canImport(NIOPosix)`).
let nioPlatforms: [Platform] = [.macOS, .iOS, .tvOS, .watchOS, .visionOS, .linux, .android]

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
        .library(name: "WebSocketClientNIO", targets: ["WebSocketClientNIO"]),
        .library(name: "BonjourService", targets: ["BonjourService"]),
        .library(name: "MQTT", targets: ["MQTT"]),
        .library(name: "MQTTClient", targets: ["MQTTClient"]),
        .library(name: "MQTTBroker", targets: ["MQTTBroker"]),
        .library(name: "MQTTBridge", targets: ["MQTTBridge"]),
        .library(name: "MQTTNWConnection", targets: ["MQTTNWConnection"]),
        .library(name: "MQTTNIO", targets: ["MQTTNIO"]),
        .library(name: "MQTTWebSocket", targets: ["MQTTWebSocket"]),
    ],
    dependencies: [
        .package(url: "https://github.com/luizmb/FP.git", from: "3.0.0"),
        .package(url: "https://github.com/luizmb/ReactiveConcurrency.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.37.0"),
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
        // NetworkServer is built on swift-nio (NIOPosix): Posix-only, so gated out of Windows (see nioPlatforms).
        .target(
            name: "NetworkServer",
            dependencies: [
                "Core",
                .product(name: "FP", package: "FP"),
                .product(name: "NIOCore", package: "swift-nio", condition: .when(platforms: nioPlatforms)),
                .product(name: "NIOPosix", package: "swift-nio", condition: .when(platforms: nioPlatforms)),
                .product(name: "NIOHTTP1", package: "swift-nio", condition: .when(platforms: nioPlatforms)),
            ] + rcFull
        ),
        .target(
            name: "WebSocketClient",
            dependencies: [
                "Core",
                .product(name: "FP", package: "FP"),
            ] + rc
        ),
        // SwiftNIO WebSocket client: a WebSocketConnection factory for every NIO platform.
        .target(
            name: "WebSocketClientNIO",
            dependencies: [
                "WebSocketClient",
                .product(name: "FP", package: "FP"),
                .product(name: "NIOCore", package: "swift-nio", condition: .when(platforms: nioPlatforms)),
                .product(name: "NIOPosix", package: "swift-nio", condition: .when(platforms: nioPlatforms)),
                .product(name: "NIOHTTP1", package: "swift-nio", condition: .when(platforms: nioPlatforms)),
                .product(name: "NIOWebSocket", package: "swift-nio", condition: .when(platforms: nioPlatforms)),
                .product(name: "NIOSSL", package: "swift-nio-ssl", condition: .when(platforms: nioPlatforms)),
            ] + rc
        ),
        .target(
            name: "BonjourService",
            dependencies: [
                "Core",
                .product(name: "FP", package: "FP"),
            ] + rc
        ),
        .target(
            name: "MQTT",
            dependencies: [
                "Core",
                .product(name: "FP", package: "FP"),
            ] + rc
        ),
        .target(
            name: "MQTTClient",
            dependencies: [
                "MQTT",
                .product(name: "FP", package: "FP"),
            ] + rc
        ),
        .target(
            name: "MQTTBroker",
            dependencies: [
                "MQTT",
                .product(name: "FP", package: "FP"),
            ] + rc
        ),
        .target(
            name: "MQTTBridge",
            dependencies: [
                "MQTT",
                "MQTTClient",
                .product(name: "FP", package: "FP"),
            ] + rc
        ),
        // Network.framework transport: Apple platforms only (sources are `#if canImport(Network)`).
        .target(
            name: "MQTTNWConnection",
            dependencies: [
                "MQTT",
                .product(name: "FP", package: "FP"),
            ] + rc
        ),
        // SwiftNIO transport: same gating as NetworkServer (see nioPlatforms).
        .target(
            name: "MQTTNIO",
            dependencies: [
                "MQTT",
                .product(name: "FP", package: "FP"),
                .product(name: "NIOCore", package: "swift-nio", condition: .when(platforms: nioPlatforms)),
                .product(name: "NIOPosix", package: "swift-nio", condition: .when(platforms: nioPlatforms)),
                .product(name: "NIOHTTP1", package: "swift-nio", condition: .when(platforms: nioPlatforms)),
                .product(name: "NIOWebSocket", package: "swift-nio", condition: .when(platforms: nioPlatforms)),
                .product(name: "NIOSSL", package: "swift-nio-ssl", condition: .when(platforms: nioPlatforms)),
            ] + rc
        ),
        .target(
            name: "MQTTWebSocket",
            dependencies: [
                "MQTT",
                "WebSocketClient",
                .product(name: "FP", package: "FP"),
            ] + rc
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: [
                "Core",
                .product(name: "FP", package: "FP"),
            ]
        ),
        .testTarget(
            name: "MQTTTests",
            dependencies: [
                "Core",
                "MQTT",
                .product(name: "FP", package: "FP"),
            ] + rc
        ),
        .testTarget(
            name: "MQTTBrokerTests",
            dependencies: [
                "MQTT",
                "MQTTBroker",
                .product(name: "FP", package: "FP"),
            ] + rc
        ),
        .testTarget(
            name: "MQTTBridgeTests",
            dependencies: [
                "MQTT",
                "MQTTBridge",
                "MQTTClient",
                .product(name: "FP", package: "FP"),
            ] + rc
        ),
        .testTarget(
            name: "MQTTClientTests",
            dependencies: [
                "MQTT",
                "MQTTClient",
                .product(name: "FP", package: "FP"),
            ] + rc
        ),
        .testTarget(
            name: "MQTTTransportTests",
            dependencies: [
                "MQTT",
                "MQTTBridge",
                "MQTTBroker",
                "MQTTClient",
                "MQTTNIO",
                "MQTTNWConnection",
                "MQTTWebSocket",
                "WebSocketClient",
                "WebSocketClientNIO",
                .product(name: "FP", package: "FP"),
                .product(name: "NIOCore", package: "swift-nio", condition: .when(platforms: nioPlatforms)),
                .product(name: "NIOPosix", package: "swift-nio", condition: .when(platforms: nioPlatforms)),
                .product(name: "NIOHTTP1", package: "swift-nio", condition: .when(platforms: nioPlatforms)),
                .product(name: "NIOWebSocket", package: "swift-nio", condition: .when(platforms: nioPlatforms)),
                .product(name: "NIOSSL", package: "swift-nio-ssl", condition: .when(platforms: nioPlatforms)),
            ] + rc
        ),
        .testTarget(
            name: "HTMLTemplatingTests",
            dependencies: [
                "HTMLTemplating",
                .product(name: "FP", package: "FP"),
            ]
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
                .product(name: "NIOHTTP1", package: "swift-nio", condition: .when(platforms: nioPlatforms)),
            ] + rcFull
        ),
    ]
)
