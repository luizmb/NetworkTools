// SPDX-License-Identifier: Apache-2.0

#if canImport(NIOPosix)
import FP
import MQTT
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOSSL
import NIOWebSocket
import ReactiveConcurrency

public extension Listener {
    /// Binds a SwiftNIO TCP listener, optionally TLS (Apple platforms, Linux, Android).
    ///
    /// The publisher binds when subscribed and emits the bound port with the listener. Subscribing to
    /// the listener's `accept` emits every accepted connection; cancelling it closes the socket.
    ///
    /// ```swift
    /// let bound = Listener.nio(host: "0.0.0.0", port: 1883, tls: nil).runReader(NIOWorld(group: group))
    /// ```
    /// - Parameters:
    ///   - host: The address to bind (`0.0.0.0` for every interface).
    ///   - port: The port to bind (`0` lets the system choose).
    ///   - tls: The server TLS configuration (certificate chain and key), or `nil` for plain TCP.
    /// - Returns: A lazy publisher of the bound listener, waiting for its world.
    static func nio(host: String, port: Int, tls: TLSConfiguration?) -> Reader<NIOWorld, Publisher<BoundListener, TransportError>> {
        Reader { world in
            serverContext(tls).flatMap(maxPublishers: 1) { context in
                bind(host: host, port: port, group: world.group) { channel, accepted in
                    let (inbound, sink) = AsyncStream<Result<[UInt8], TransportError>>.makeStream()
                    if let context {
                        try channel.pipeline.syncOperations.addHandler(NIOSSLServerHandler(context: context))
                    }
                    try channel.pipeline.syncOperations.addHandler(InboundBytes(sink))
                    accepted.yield(transportConnection(channel, inbound: inbound))
                }
            }
        }
    }

    /// Binds a SwiftNIO MQTT-over-WebSocket listener: HTTP/1.1 upgrade on `path` offering the `mqtt`
    /// subprotocol, then MQTT bytes in binary frames; over TLS (`wss://`) when given a configuration.
    ///
    /// ```swift
    /// let bound = Listener.nioWebSocket(host: "0.0.0.0", port: 9001, path: "/mqtt", maximumMessageSize: 1 << 20, tls: nil)
    ///     .runReader(NIOWorld(group: group))
    /// ```
    /// - Parameters:
    ///   - host: The address to bind.
    ///   - port: The port to bind (`0` lets the system choose).
    ///   - path: The request path to accept, e.g. `/mqtt`.
    ///   - maximumMessageSize: The largest WebSocket message accepted, in bytes.
    ///   - tls: The server TLS configuration (certificate chain and key), or `nil` for plain `ws://`.
    /// - Returns: A lazy publisher of the bound listener, waiting for its world.
    static func nioWebSocket(
        host: String,
        port: Int,
        path: String,
        maximumMessageSize: Int,
        tls: TLSConfiguration?
    ) -> Reader<NIOWorld, Publisher<BoundListener, TransportError>> {
        Reader { world in
            serverContext(tls).flatMap(maxPublishers: 1) { context in
                bindWebSocket(host: host, port: port, path: path, maximumMessageSize: maximumMessageSize, tls: context, group: world.group)
            }
        }
    }
}

private func serverContext(_ tls: TLSConfiguration?) -> Publisher<NIOSSLContext?, TransportError> {
    do {
        return try .just(tls.map(NIOSSLContext.init(configuration:)))
    } catch {
        return .fail(.connectionFailed(String(describing: error)))
    }
}

private func bindWebSocket(
    host: String,
    port: Int,
    path: String,
    maximumMessageSize: Int,
    tls: NIOSSLContext?,
    group: any EventLoopGroup
) -> Publisher<BoundListener, TransportError> {
    bind(host: host, port: port, group: group) { channel, accepted in
        let upgrader = NIOWebSocketServerUpgrader(
            maxFrameSize: maximumMessageSize,
            shouldUpgrade: { channel, head in
                let offersMQTT = head.headers["Sec-WebSocket-Protocol"]
                    .flatMap { $0.split(separator: ",") }
                    .contains { $0.trimmingCharacters(in: .whitespaces) == "mqtt" }
                let accepted = head.uri.split(separator: "?").first.map(String.init) == path && offersMQTT
                return channel.eventLoop.makeSucceededFuture(accepted ? HTTPHeaders([("Sec-WebSocket-Protocol", "mqtt")]) : nil)
            },
            upgradePipelineHandler: { channel, _ in
                channel.eventLoop.makeCompletedFuture {
                    let (inbound, sink) = AsyncStream<Result<[UInt8], TransportError>>.makeStream()
                    try channel.pipeline.syncOperations.addHandlers([
                        NIOWebSocketFrameAggregator(
                            minNonFinalFragmentSize: 0,
                            maxAccumulatedFrameCount: .max,
                            maxAccumulatedFrameSize: maximumMessageSize
                        ),
                        WebSocketBytes(),
                        InboundBytes(sink),
                    ])
                    accepted.yield(transportConnection(channel, inbound: inbound))
                }
            }
        )
        if let tls {
            try channel.pipeline.syncOperations.addHandler(NIOSSLServerHandler(context: tls))
        }
        try channel.pipeline.syncOperations.configureHTTPServerPipeline(
            withServerUpgrade: (upgraders: [upgrader], completionHandler: { _ in })
        )
    }
}

private func bind(
    host: String,
    port: Int,
    group: any EventLoopGroup,
    child: @escaping @Sendable (any Channel, AsyncStream<TransportConnection>.Continuation) throws -> Void
) -> Publisher<BoundListener, TransportError> {
    .future { () async -> Result<BoundListener, TransportError> in
        let (accepted, sink) = AsyncStream<TransportConnection>.makeStream()
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.tcpOption(.tcp_nodelay), value: 1)
            .childChannelInitializer { channel in
                channel.eventLoop.makeCompletedFuture { try child(channel, sink) }
            }
        let server: any Channel
        do {
            server = try await bootstrap.bind(host: host, port: port).get()
        } catch {
            return .failure(.connectionFailed(String(describing: error)))
        }
        let listener = Listener {
            Publisher<TransportConnection, TransportError> { continuation async throws(TransportError) in
                await withTaskCancellationHandler {
                    for await connection in accepted {
                        continuation.yield(connection)
                    }
                    continuation.finish()
                } onCancel: {
                    server.close(promise: nil)
                    sink.finish()
                }
            }
        }
        return .success(BoundListener(port: server.localAddress?.port ?? port, listener: listener))
    }
}

/// Server side of MQTT over WebSocket: binary frames in, bytes to the next handler; bytes out,
/// unmasked binary frames. Answers pings and the closing handshake.
private final class WebSocketBytes: ChannelDuplexHandler, Sendable {
    typealias InboundIn = WebSocketFrame
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = WebSocketFrame

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        switch frame.opcode {
        case .binary:
            context.fireChannelRead(wrapInboundOut(frame.unmaskedData))
        case .ping:
            context.writeAndFlush(wrapOutboundOut(WebSocketFrame(fin: true, opcode: .pong, data: frame.unmaskedData)), promise: nil)
        case .connectionClose:
            let channel = context.channel
            context.writeAndFlush(wrapOutboundOut(WebSocketFrame(fin: true, opcode: .connectionClose, data: frame.unmaskedData)))
                .whenComplete { _ in channel.close(promise: nil) }
        default:
            break
        }
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        context.write(wrapOutboundOut(WebSocketFrame(fin: true, opcode: .binary, data: unwrapOutboundIn(data))), promise: promise)
    }
}
#endif
