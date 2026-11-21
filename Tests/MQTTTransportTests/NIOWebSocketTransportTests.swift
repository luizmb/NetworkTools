// SPDX-License-Identifier: Apache-2.0

#if canImport(NIOPosix)
import Foundation
import FP
import MQTT
import MQTTWebSocket
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOWebSocket
import ReactiveConcurrency
import Testing
import WebSocketClient
import WebSocketClientNIO

/// Server side of the tests: WebSocket frames in, raw bytes to the next handler, and back. Test-only.
private final class FramesToBytes: ChannelDuplexHandler, @unchecked Sendable {
    typealias InboundIn = WebSocketFrame
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = WebSocketFrame

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        guard frame.opcode == .binary else { return }
        context.fireChannelRead(wrapInboundOut(frame.unmaskedData))
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        context.write(wrapOutboundOut(WebSocketFrame(fin: true, opcode: .binary, data: unwrapOutboundIn(data))), promise: promise)
    }
}

/// Echoes text and binary frames, and answers pings. Test-only.
private final class EchoFrames: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        switch frame.opcode {
        case .text,
             .binary:
            context.writeAndFlush(wrapOutboundOut(WebSocketFrame(fin: true, opcode: frame.opcode, data: frame.unmaskedData)), promise: nil)
        case .ping:
            context.writeAndFlush(wrapOutboundOut(WebSocketFrame(fin: true, opcode: .pong, data: frame.unmaskedData)), promise: nil)
        default:
            break
        }
    }
}

private func startWebSocketServer(
    _ group: any EventLoopGroup,
    handlers: @escaping @Sendable () -> [any ChannelHandler & Sendable]
) async throws -> any Channel {
    try await ServerBootstrap(group: group)
        .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
        .childChannelInitializer { channel in
            let upgrader = NIOWebSocketServerUpgrader(
                shouldUpgrade: { channel, head in
                    channel.eventLoop.makeSucceededFuture(
                        head.headers["Sec-WebSocket-Protocol"].first.map { HTTPHeaders([("Sec-WebSocket-Protocol", $0)]) } ?? HTTPHeaders()
                    )
                },
                upgradePipelineHandler: { channel, _ in
                    channel.eventLoop.makeCompletedFuture { try channel.pipeline.syncOperations.addHandlers(handlers()) }
                }
            )
            return channel.pipeline.configureHTTPServerPipeline(withServerUpgrade: (upgraders: [upgrader], completionHandler: { _ in }))
        }
        .bind(host: "127.0.0.1", port: 0)
        .get()
}

private func open(port: Int, group: any EventLoopGroup) -> Publisher<WebSocketConnection, WebSocketNIOError> {
    WebSocketConnection
        .nio(host: "127.0.0.1", port: port, path: "/mqtt", protocols: ["mqtt"], maximumMessageSize: 1 << 16, tls: nil)
        .runReader(WebSocketNIOWorld(group: group, random: SplitMix64(seed: 42)))
}

@Suite struct NIOWebSocketTransportTests {
    @Test func echoesMaskedFrames() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let server = try await startWebSocketServer(group) { [EchoFrames()] }
        let port = try #require(server.localAddress?.port)

        let result = await open(port: port, group: group)
            .flatMap(maxPublishers: 1) { socket in
                socket.send(.text("hello"))
                    .mapError { WebSocketNIOError.sendFailed(String(describing: $0)) }
                    .flatMap(maxPublishers: 1) { _ in socket.receive.mapError { WebSocketNIOError.connectionLost(String(describing: $0)) } }
                    .prefix(1)
            }
            .firstResultTask()
            .run()
        #expect(result == .success(.text("hello")))

        try await server.close().get()
        try await group.shutdownGracefully()
    }

    @Test func pingIsAnsweredByPong() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let server = try await startWebSocketServer(group) { [EchoFrames()] }
        let port = try #require(server.localAddress?.port)

        let result = await open(port: port, group: group)
            .flatMap(maxPublishers: 1) { socket in
                // WebSocketConnection closes on deinit: keep it alive until the pong arrives.
                socket.ping
                    .map { withExtendedLifetime(socket) { true } }
                    .mapError { WebSocketNIOError.connectionLost(String(describing: $0)) }
            }
            .firstResultTask()
            .run()
        #expect(result == .success(true))

        try await server.close().get()
        try await group.shutdownGracefully()
    }

    @Test func refusedConnectionIsTyped() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let result = await open(port: 1, group: group).firstResultTask().run()
        guard case .failure(.connectionFailed) = result else {
            Issue.record("expected connectionFailed, got \(String(describing: result))")
            return
        }
        try await group.shutdownGracefully()
    }

    @Test func mqttSessionOverNIOWebSocket() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let server = try await startWebSocketServer(group) { [FramesToBytes(), TinyBroker()] }
        let port = try #require(server.localAddress?.port)

        let received = try await subscribeAndReceive(over: .webSocket { open(port: port, group: group) })
        #expect(received.count == 3)
        #expect(lastPayload(received) == Array("hello".utf8))

        try await server.close().get()
        try await group.shutdownGracefully()
    }
}
#endif
