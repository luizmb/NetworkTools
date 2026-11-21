// SPDX-License-Identifier: Apache-2.0

#if canImport(NIOPosix)
import FP
import MQTT
import MQTTBridge
import MQTTBroker
import MQTTClient
import MQTTNIO
import NIOCore
import NIOPosix
import ReactiveConcurrency
import Testing

private let memoryTicks: @Sendable () -> Publisher<Duration, Never> = {
    .monotonicTicks(every: .milliseconds(20), clock: ContinuousClock())
}

private func options(_ name: String) -> ClientOptions {
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

/// Subscribes to `filter` in one session while another publishes `message` (retained); returns
/// what the subscriber receives.
private func exchange(
    subscribeOver subscriberWorld: ClientWorld,
    publishOver publisherWorld: ClientWorld,
    filter: TopicFilter,
    message: OutgoingMessage
) async -> String? {
    let subscriber = MQTTClient.session(
        options("sub"),
        requests: [ClientRequest.subscribe([Subscription(filter: filter, options: .qos(.atLeastOnce))], properties: [])].publisher
    )
    .runReader(subscriberWorld)
    let publisher = MQTTClient.session(options("pub"), requests: [ClientRequest.publish(message)].publisher).runReader(publisherWorld)
    let received = await subscriber
        .compactMap { event -> String? in
            guard case let .message(publish) = event else { return nil }
            return "\(publish.topic.rawValue)=\(String(bytes: publish.payload, encoding: .utf8) ?? "")"
        }
        .merge(with: publisher.compactMap(const(String?.none)))
        .prefix(1)
        .firstResultTask()
        .run()
    return try? received?.get()
}

@Suite struct InMemoryLinkTests {
    @Test func clientAndBrokerWithoutANetwork() async throws {
        let link = InMemoryLink.make()
        let broker = MQTTBroker.serve(BrokerOptions(), policy: .open, publications: .empty())
            .runReader(BrokerWorld(listener: link.listener, clock: memoryTicks))
            .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
        let world = ClientWorld(transport: link.transport, clock: memoryTicks)
        let message = OutgoingMessage(
            topic: try #require(TopicName(rawValue: "mem/a")),
            payload: Array("in memory".utf8),
            qos: .atLeastOnce,
            retain: true,
            properties: []
        )
        let received = await exchange(
            subscribeOver: world,
            publishOver: world,
            filter: try #require(TopicFilter(rawValue: "mem/+")),
            message: message
        )
        #expect(received == "mem/a=in memory")
        broker.cancel()
    }

    @Test func bridgeLinkedInProcessToItsLocalBroker() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let link = InMemoryLink.make()
        let local = try await bindNIO(group: group)
        let remote = try await bindNIO(group: group)
        let brokers = [
            BrokerWorld(listener: .merge([local.listener, link.listener]), clock: memoryTicks),
            BrokerWorld(listener: remote.listener, clock: memoryTicks),
        ].map { world in
            MQTTBroker.serve(BrokerOptions(), policy: .open, publications: .empty())
                .runReader(world)
                .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
        }
        let rule = BridgeRule(
            filter: try #require(TopicFilter(rawValue: "printer/#")),
            direction: .outbound,
            qos: .atLeastOnce,
            localPrefix: "",
            remotePrefix: "home/"
        )
        let bridge = MQTTBridge.run(rules: [rule], local: options("bridge-local"), remote: options("bridge-remote"))
            .runReader(BridgeWorld(
                local: ClientWorld(transport: link.transport, clock: memoryTicks),
                remote: ClientWorld(transport: nioTransport(port: remote.port, group: group), clock: memoryTicks)
            ))
            .sink(receiveCompletion: { _ in }, receiveValue: { _ in })

        let message = OutgoingMessage(
            topic: try #require(TopicName(rawValue: "printer/status")),
            payload: Array("printing".utf8),
            qos: .atLeastOnce,
            retain: true,
            properties: []
        )
        let received = await exchange(
            subscribeOver: ClientWorld(transport: nioTransport(port: remote.port, group: group), clock: memoryTicks),
            publishOver: ClientWorld(transport: nioTransport(port: local.port, group: group), clock: memoryTicks),
            filter: try #require(TopicFilter(rawValue: "home/printer/+")),
            message: message
        )
        #expect(received == "home/printer/status=printing")
        bridge.cancel()
        brokers.forEach { $0.cancel() }
        try await group.shutdownGracefully()
    }
}
#endif
