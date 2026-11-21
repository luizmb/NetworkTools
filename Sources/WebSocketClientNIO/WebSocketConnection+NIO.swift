// SPDX-License-Identifier: Apache-2.0

#if canImport(NIOPosix)
import Foundation
import FP
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOSSL
import NIOWebSocket
import ReactiveConcurrency
import WebSocketClient

/// Why a SwiftNIO WebSocket could not be opened or used.
public enum WebSocketNIOError: Error, Sendable, Hashable {
    /// The TCP connection (or the TLS handshake) could not be completed.
    case connectionFailed(String)
    /// The server did not accept the WebSocket upgrade.
    case upgradeRejected
    /// The open connection broke.
    case connectionLost(String)
    /// A frame could not be written.
    case sendFailed(String)
}

public extension WebSocketConnection {
    /// Opens a WebSocket over SwiftNIO (Apple platforms, Linux and Android).
    ///
    /// Each subscription performs a new HTTP/1.1 upgrade handshake and emits the open connection
    /// once the server has switched protocols. Fragmented messages are reassembled, pings are
    /// answered automatically, and every outgoing frame is masked as RFC 6455 requires. With a TLS
    /// configuration the connection is `wss://` (swift-nio-ssl); without one, plain `ws://`.
    ///
    /// The event loop group and the random generator are effects: they come from the
    /// ``WebSocketNIOWorld`` the application supplies at its boundary.
    ///
    /// ```swift
    /// let world = WebSocketNIOWorld(group: group, random: SystemRandomNumberGenerator())
    /// let socket = WebSocketConnection
    ///     .nio(host: "192.168.1.20", port: 9001, path: "/mqtt", protocols: ["mqtt"], maximumMessageSize: 1 << 20, tls: nil)
    ///     .runReader(world)
    /// let secure = WebSocketConnection
    ///     .nio(host: "broker.example.com", port: 443, path: "/mqtt", protocols: ["mqtt"], maximumMessageSize: 1 << 20,
    ///          tls: .makeClientConfiguration())
    ///     .runReader(world)
    /// ```
    /// - Parameters:
    ///   - host: The server's host name or IP address (also the TLS server name).
    ///   - port: The server's TCP port.
    ///   - path: The request path, e.g. `/` or `/mqtt`.
    ///   - protocols: Subprotocols offered in `Sec-WebSocket-Protocol` (e.g. `["mqtt"]`).
    ///   - maximumMessageSize: The largest message accepted, in bytes.
    ///   - tls: The TLS configuration for `wss://`, or `nil` for plain `ws://`.
    /// - Returns: The connection, waiting for its world.
    static func nio(
        host: String,
        port: Int,
        path: String,
        protocols: [String],
        maximumMessageSize: Int,
        tls: TLSConfiguration?
    ) -> Reader<WebSocketNIOWorld, Publisher<WebSocketConnection, WebSocketNIOError>> {
        Reader { world in
            .future { () async -> Result<WebSocketConnection, WebSocketNIOError> in
                let context: NIOSSLContext?
                do {
                    context = try tls.map(NIOSSLContext.init(configuration:))
                } catch {
                    return .failure(.connectionFailed(String(describing: error)))
                }
                let randomness = GeneratorBox(world.random)
                let (inbound, sink) = AsyncStream<Result<WebSocketMessage, WebSocketNIOError>>.makeStream()
                let frames = FrameHandler(sink: sink, randomness: randomness)
                let request = HTTPRequestHead(
                    version: .http1_1,
                    method: .GET,
                    uri: path,
                    headers: HTTPHeaders(
                        [("Host", "\(host):\(port)"), ("Content-Length", "0")]
                            + (protocols.isEmpty ? [] : [("Sec-WebSocket-Protocol", protocols.joined(separator: ", "))])
                    )
                )
                let upgrade = await handshake(
                    host: host,
                    port: port,
                    tls: context,
                    request: request,
                    frames: frames,
                    maximumMessageSize: maximumMessageSize,
                    group: world.group,
                    requestKey: randomness.run(WebSocketKeys.requestKey())
                )
                return upgrade.map { channel in connection(channel, frames: frames, inbound: inbound, randomness: randomness) }
            }
        }
    }
}

// MARK: - Handshake

// swiftlint:disable:next function_parameter_count
private func handshake(
    host: String,
    port: Int,
    tls: NIOSSLContext?,
    request: HTTPRequestHead,
    frames: FrameHandler,
    maximumMessageSize: Int,
    group: any EventLoopGroup,
    requestKey: String
) async -> Result<any Channel, WebSocketNIOError> {
    let negotiation: EventLoopFuture<(any Channel)?>
    do {
        negotiation = try await ClientBootstrap(group: group).connect(host: host, port: port) { channel in
            channel.eventLoop.makeCompletedFuture {
                if let tls {
                    try channel.pipeline.syncOperations.addHandler(
                        NIOSSLClientHandler(context: tls, serverHostname: host.isIPAddress ? nil : host)
                    )
                }
                let upgrader = NIOTypedWebSocketClientUpgrader<(any Channel)?>(
                    requestKey: requestKey,
                    maxFrameSize: maximumMessageSize,
                    upgradePipelineHandler: { channel, _ in
                        channel.eventLoop.makeCompletedFuture {
                            try channel.pipeline.syncOperations.addHandlers([
                                NIOWebSocketFrameAggregator(
                                    minNonFinalFragmentSize: 0,
                                    maxAccumulatedFrameCount: .max,
                                    maxAccumulatedFrameSize: maximumMessageSize
                                ),
                                frames,
                            ])
                            return channel
                        }
                    }
                )
                return try channel.pipeline.syncOperations.configureUpgradableHTTPClientPipeline(
                    configuration: .init(upgradeConfiguration: NIOTypedHTTPClientUpgradeConfiguration(
                        upgradeRequestHead: request,
                        upgraders: [upgrader],
                        notUpgradingCompletionHandler: { channel in
                            channel.close(promise: nil)
                            return channel.eventLoop.makeSucceededFuture(nil)
                        }
                    ))
                )
            }
        }
    } catch {
        return .failure(.connectionFailed(String(describing: error)))
    }
    do {
        return try await negotiation.get().map(Result.success) ?? .failure(.upgradeRejected)
    } catch {
        return .failure(.connectionFailed(String(describing: error)))
    }
}

private extension String {
    /// IP literals are not valid TLS server names (SNI).
    var isIPAddress: Bool {
        (try? SocketAddress(ipAddress: self, port: 0)) != nil
    }
}

// MARK: - Connection

private func connection(
    _ channel: any Channel,
    frames: FrameHandler,
    inbound: AsyncStream<Result<WebSocketMessage, WebSocketNIOError>>,
    randomness: GeneratorBox
) -> WebSocketConnection {
    WebSocketConnection(
        receive: Publisher<WebSocketMessage, any Error> { continuation async throws(any Error) in
            await withTaskCancellationHandler {
                for await message in inbound {
                    switch message {
                    case let .success(value): continuation.yield(value)
                    case let .failure(error): return continuation.fail(error)
                    }
                }
                continuation.finish()
            } onCancel: {
                channel.close(promise: nil)
            }
        },
        send: { message in
            .future { () async -> Result<Void, any Error> in
                await write(frame(message, maskKey: randomness.maskingKey), to: channel)
                    .mapError { $0 as any Error }
            }
        },
        ping: .future { () async -> Result<Void, any Error> in
            await frames.ping(on: channel).mapError { $0 as any Error }
        },
        cancel: {
            // No promises here: this runs from `deinit`, possibly after the event loop group shut down,
            // where a promise could never be completed.
            channel.writeAndFlush(
                WebSocketFrame(fin: true, opcode: .connectionClose, maskKey: randomness.maskingKey, data: ByteBuffer()),
                promise: nil
            )
            channel.close(promise: nil)
        }
    )
}

private func frame(_ message: WebSocketMessage, maskKey: WebSocketMaskingKey) -> WebSocketFrame {
    switch message {
    case let .text(text): WebSocketFrame(fin: true, opcode: .text, maskKey: maskKey, data: ByteBuffer(string: text))
    case let .data(data): WebSocketFrame(fin: true, opcode: .binary, maskKey: maskKey, data: ByteBuffer(bytes: data))
    }
}

private func write(_ frame: WebSocketFrame, to channel: any Channel) async -> Result<Void, WebSocketNIOError> {
    do {
        try await channel.writeAndFlush(frame).get()
        return .success(())
    } catch {
        return .failure(.sendFailed(String(describing: error)))
    }
}

// MARK: - Frame handler

/// Turns whole (aggregated) frames into messages, answers pings and the closing handshake, and
/// resolves pending `ping`s when their pong arrives.
///
/// `@unchecked Sendable`: `pongWaiters` is only touched on the channel's event loop
/// (`channelRead` runs there and ``ping(on:)`` hops there before touching it).
private final class FrameHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    private let sink: AsyncStream<Result<WebSocketMessage, WebSocketNIOError>>.Continuation
    private let randomness: GeneratorBox
    private var pongWaiters: [CheckedContinuation<Result<Void, WebSocketNIOError>, Never>] = []

    init(sink: AsyncStream<Result<WebSocketMessage, WebSocketNIOError>>.Continuation, randomness: GeneratorBox) {
        self.sink = sink
        self.randomness = randomness
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        switch frame.opcode {
        case .binary:
            sink.yield(.success(.data(Data(frame.unmaskedData.readableBytesView))))
        case .text:
            sink.yield(.success(.text(String(buffer: frame.unmaskedData))))
        case .ping:
            let pong = WebSocketFrame(fin: true, opcode: .pong, maskKey: randomness.maskingKey, data: frame.unmaskedData)
            context.writeAndFlush(wrapOutboundOut(pong), promise: nil)
        case .pong:
            let waiters = pongWaiters
            pongWaiters = []
            waiters.forEach { $0.resume(returning: .success(())) }
        case .connectionClose:
            let reply = WebSocketFrame(fin: true, opcode: .connectionClose, maskKey: randomness.maskingKey, data: frame.unmaskedData)
            let channel = context.channel
            context.writeAndFlush(wrapOutboundOut(reply)).whenComplete { _ in channel.close(promise: nil) }
        default:
            break
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        let waiters = pongWaiters
        pongWaiters = []
        waiters.forEach { $0.resume(returning: .failure(.connectionLost("closed"))) }
        sink.finish()
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        sink.yield(.failure(.connectionLost(String(describing: error))))
        sink.finish()
        context.close(promise: nil)
    }

    func ping(on channel: any Channel) async -> Result<Void, WebSocketNIOError> {
        await withCheckedContinuation { continuation in
            channel.eventLoop.execute {
                self.pongWaiters.append(continuation)
                let ping = WebSocketFrame(fin: true, opcode: .ping, maskKey: self.randomness.maskingKey, data: ByteBuffer())
                channel.writeAndFlush(ping).whenFailure { error in
                    let waiters = self.pongWaiters
                    self.pongWaiters = []
                    waiters.forEach { $0.resume(returning: .failure(.sendFailed(String(describing: error)))) }
                }
            }
        }
    }
}
#endif
