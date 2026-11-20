// SPDX-License-Identifier: Apache-2.0

#if canImport(NIOPosix)
import Foundation
import MQTT
import MQTTNIO
import NIOCore
import NIOSSL
import ReactiveConcurrency
import Testing

/// Binds a SwiftNIO TCP listener on a free loopback port.
func bindNIO(tls: TLSConfiguration? = nil, group: any EventLoopGroup) async throws -> BoundListener {
    let bound = Listener.nio(host: "127.0.0.1", port: 0, tls: tls).runReader(NIOWorld(group: group))
    return try #require(try await bound.firstResultTask().run()?.get())
}

/// Binds a SwiftNIO MQTT-over-WebSocket listener on a free loopback port, path `/mqtt`.
func bindNIOWebSocket(group: any EventLoopGroup) async throws -> BoundListener {
    let bound = Listener.nioWebSocket(host: "127.0.0.1", port: 0, path: "/mqtt", maximumMessageSize: 1 << 16)
        .runReader(NIOWorld(group: group))
    return try #require(try await bound.firstResultTask().run()?.get())
}

/// A SwiftNIO TCP transport to a loopback port.
func nioTransport(port: Int, group: any EventLoopGroup) -> Transport {
    Transport.nio(host: "127.0.0.1", port: port, tls: nil).runReader(NIOWorld(group: group))
}
#endif
