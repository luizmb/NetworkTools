// SPDX-License-Identifier: Apache-2.0

#if canImport(NIOPosix)
import FP
import MQTT
import MQTTClient
import MQTTNIO
import NIOCore
import NIOPosix
import ReactiveConcurrency
import Testing

// swiftlint:disable:next force_unwrapping
private let topicAB = TopicName(rawValue: "a/b")!

/// A loopback MQTT "broker" good enough for one session: answers CONNECT and SUBSCRIBE,
/// publishes one message after SUBSCRIBE, and closes on DISCONNECT. Test-only.
final class TinyBroker: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private var stream = PacketStream(version: .v3_1_1, maximumPacketSize: 1 << 16)

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        let (result, next) = PacketStream.feed(buffer.readBytes(length: buffer.readableBytes) ?? []).runStateful(stream)
        stream = next
        for packet in (try? result.get()) ?? [] {
            for reply in replies(packet) {
                context.write(wrapOutboundOut(ByteBuffer(bytes: (try? reply.encode(for: .v3_1_1).get()) ?? [])), promise: nil)
            }
            context.flush()
            if packet.type == .disconnect { context.close(promise: nil) }
        }
    }

    private func replies(_ packet: Packet) -> [Packet] {
        switch packet {
        case .connect:
            [.connAck(ConnAck(sessionPresent: false, reasonCode: .success, properties: []))]
        case let .subscribe(subscribe):
            [
                .subAck(SubAck(packetIdentifier: subscribe.packetIdentifier, reasonCodes: [.grantedQoS0], properties: [])),
                .publish(Publish(
                    topic: topicAB,
                    payload: Array("hello".utf8),
                    delivery: .atMostOnce,
                    retain: false,
                    duplicate: false,
                    properties: []
                )),
            ]
        default:
            []
        }
    }
}

func startBroker(_ group: any EventLoopGroup) async throws -> any Channel {
    try await ServerBootstrap(group: group)
        .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
        .childChannelInitializer { channel in
            channel.eventLoop.makeCompletedFuture { try channel.pipeline.syncOperations.addHandler(TinyBroker()) }
        }
        .bind(host: "127.0.0.1", port: 0)
        .get()
}

let loopbackOptions = ClientOptions(
    version: .v3_1_1,
    clientIdentifier: "loopback-test",
    cleanStart: true,
    keepAlive: 0,
    will: nil,
    userName: nil,
    password: nil,
    properties: [],
    maximumPacketSize: 1 << 16
)

/// Connects, subscribes to `a/b` and collects the first three events (connected, subscribed, message).
func subscribeAndReceive(over transport: Transport) async throws -> [ClientEvent] {
    let filter = try #require(TopicFilter(rawValue: "a/b"))
    let result = await MQTTClient.session(
        loopbackOptions,
        requests: [ClientRequest.subscribe([Subscription(filter: filter, options: .qos(.atMostOnce))], properties: [])].publisher
    )
    .runReader(ClientWorld(transport: transport, clock: const(.empty())))
    .prefix(3)
    .collect()
    .firstResultTask()
    .run()
    return try #require(try result?.get())
}

func lastPayload(_ events: [ClientEvent]) -> [UInt8] {
    guard case let .message(publish) = events.last else { return [] }
    return publish.payload
}

@Suite struct NIOTransportTests {
    @Test func clientSessionOverLoopbackTCP() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let server = try await startBroker(group)
        let port = try #require(server.localAddress?.port)
        let received = try await subscribeAndReceive(over: nioTransport(port: port, group: group))
        #expect(received.count == 3)
        #expect(lastPayload(received) == Array("hello".utf8))

        try await server.close().get()
        try await group.shutdownGracefully()
    }

    @Test func refusedConnectionIsTyped() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let result = await nioTransport(port: 1, group: group).connect().firstResultTask().run()
        guard case .failure(.connectionFailed) = result else {
            Issue.record("expected connectionFailed, got \(String(describing: result))")
            return
        }
        try await group.shutdownGracefully()
    }
}
#endif
