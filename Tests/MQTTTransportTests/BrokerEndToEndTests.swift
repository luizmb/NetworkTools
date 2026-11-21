// SPDX-License-Identifier: Apache-2.0

#if canImport(NIOPosix)
import Dispatch
import FP
import MQTT
import MQTTBroker
import MQTTClient
import MQTTNIO
import MQTTWebSocket
import NIOCore
import NIOPosix
import ReactiveConcurrency
import Testing
import WebSocketClient
import WebSocketClientNIO
#if canImport(Network)
import MQTTNWConnection
#endif

private let ticks: @Sendable () -> Publisher<Duration, Never> = {
    .monotonicTicks(every: .milliseconds(20), clock: ContinuousClock())
}

private func clientOptions(_ name: String) -> ClientOptions {
    ClientOptions(
        version: .v5,
        clientIdentifier: name,
        cleanStart: true,
        keepAlive: 30,
        will: nil,
        userName: nil,
        password: nil,
        properties: [],
        maximumPacketSize: 1 << 16
    )
}

/// Starts a broker on `bound`, then a subscriber and a publisher over `transport`; returns the
/// payload the subscriber receives. The message is retained, so it arrives whichever client
/// connects first.
private func roundTrip(bound: BoundListener, transport: Transport) async -> String? {
    let broker = MQTTBroker.serve(BrokerOptions(), policy: .open, publications: .empty())
        .runReader(BrokerWorld(listener: bound.listener, clock: ticks))
    let running = broker.sink(receiveCompletion: { _ in }, receiveValue: { _ in })
    defer { running.cancel() }

    guard let topicFilter = TopicFilter(rawValue: "e2e/+"), let name = TopicName(rawValue: "e2e/hello") else { return nil }
    let world = ClientWorld(transport: transport, clock: ticks)
    let subscribe = ClientRequest.subscribe([Subscription(filter: topicFilter, options: .qos(.atLeastOnce))], properties: [])
    let message = OutgoingMessage(topic: name, payload: Array("hi".utf8), qos: .atLeastOnce, retain: true, properties: [])
    let publish = ClientRequest.publish(message)
    let subscriber = MQTTClient.session(clientOptions("sub"), requests: [subscribe].publisher).runReader(world)
    let publisher = MQTTClient.session(clientOptions("pub"), requests: [publish].publisher).runReader(world)

    let received = subscriber
        .compactMap { event -> String? in
            guard case let .message(message) = event else { return nil }
            return String(bytes: message.payload, encoding: .utf8)
        }
        .merge(with: publisher.compactMap(const(String?.none)))
        .prefix(1)
        .firstResultTask()
    return try? await received.run()?.get()
}

@Suite struct BrokerEndToEndTests {
    @Test func brokerOverNIOTCP() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let bound = try await bindNIO(group: group)
        let payload = await roundTrip(
            bound: bound,
            transport: nioTransport(port: bound.port, group: group)
        )
        #expect(payload == "hi")
        try await group.shutdownGracefully()
    }

    @Test func brokerOverNIOWebSocket() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let bound = try await bindNIOWebSocket(group: group)
        let world = WebSocketNIOWorld(group: group, random: SplitMix64(seed: 7))
        let transport = Transport.webSocket {
            WebSocketConnection
                .nio(host: "127.0.0.1", port: bound.port, path: "/mqtt", protocols: ["mqtt"], maximumMessageSize: 1 << 16)
                .runReader(world)
        }
        #expect(await roundTrip(bound: bound, transport: transport) == "hi")
        try await group.shutdownGracefully()
    }

    #if canImport(Network)
    @Test func brokerOverNetworkFramework() async throws {
        let queue = DispatchQueue(label: "nw-broker-test")
        let world = NWWorld(queue: queue)
        let listening = Listener.nwListener(port: 0, parameters: .tcp).runReader(world)
        let bound = try #require(try await listening.firstResultTask().run()?.get())
        let transport = Transport.nwConnection(host: "127.0.0.1", port: UInt16(bound.port), parameters: .tcp).runReader(world)
        #expect(await roundTrip(bound: bound, transport: transport) == "hi")
    }
    #endif
}
#endif
