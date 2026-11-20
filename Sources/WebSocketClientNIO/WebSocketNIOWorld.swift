// SPDX-License-Identifier: Apache-2.0

#if canImport(NIOPosix)
import Foundation
import FP
import NIOCore
import NIOWebSocket

/// The effects a SwiftNIO WebSocket needs, supplied at the application's boundary through `Reader`.
public struct WebSocketNIOWorld: Sendable {
    /// The event loop group channels run on.
    public let group: any EventLoopGroup
    /// The generator the handshake and masking keys (``WebSocketKeys``) run against. Each connection
    /// starts from this value, so production passes `SystemRandomNumberGenerator()`; a seeded generator
    /// (e.g. `SplitMix64`) makes tests deterministic.
    public let random: AnyRandomNumberGenerator

    /// Creates a world.
    /// - Parameters:
    ///   - group: The event loop group channels run on.
    ///   - random: The random number generator for keys.
    public init(group: any EventLoopGroup, random: some RandomNumberGenerator & Sendable) {
        self.group = group
        self.random = AnyRandomNumberGenerator(random)
    }
}

/// The random values RFC 6455 requires of a client, as `Gen` values: they run against whatever
/// generator the connection is given, so production uses the system generator and tests a seeded one.
public enum WebSocketKeys {
    /// A `Sec-WebSocket-Key`: 16 random bytes, base64-encoded (one per handshake).
    /// - Returns: The key generator.
    public static func requestKey<R: RandomNumberGenerator & Sendable>() -> Gen<R, String> {
        Gen<R, String> { NIOWebSocketClientUpgrader.randomRequestKey(using: &$0) }
    }

    /// A frame masking key: 4 random bytes (one per frame the client sends).
    /// - Returns: The masking key generator.
    public static func maskingKey<R: RandomNumberGenerator & Sendable>() -> Gen<R, WebSocketMaskingKey> {
        Gen<R, WebSocketMaskingKey> { WebSocketMaskingKey.random(using: &$0) }
    }
}

/// Runs `Gen` values against the one generator a connection owns.
///
/// `@unchecked Sendable`: the generator is mutable state, touched only under `lock`.
final class GeneratorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var generator: AnyRandomNumberGenerator

    init(_ generator: some RandomNumberGenerator & Sendable) {
        self.generator = AnyRandomNumberGenerator(generator)
    }

    func run<A>(_ gen: Gen<AnyRandomNumberGenerator, A>) -> A {
        lock.withLock { gen.run(&generator) }
    }

    var maskingKey: WebSocketMaskingKey {
        run(WebSocketKeys.maskingKey())
    }
}
#endif
