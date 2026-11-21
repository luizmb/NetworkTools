// SPDX-License-Identifier: Apache-2.0

#if canImport(NIOPosix)
import Foundation
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

private let bridgeTicks: @Sendable () -> Publisher<Duration, Never> = {
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

@Suite struct BridgeEndToEndTests {
    @Test func forwardsFromTheLocalBrokerToTheRemoteOne() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let local = try await bindNIO(group: group)
        let remote = try await bindNIO(group: group)
        let brokers = [local, remote].map { bound in
            MQTTBroker.serve(BrokerOptions(), policy: .open, publications: .empty())
                .runReader(BrokerWorld(listener: bound.listener, clock: bridgeTicks))
                .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
        }

        let localWorld = ClientWorld(
            transport: nioTransport(port: local.port, group: group),
            clock: bridgeTicks
        )
        let remoteWorld = ClientWorld(
            transport: nioTransport(port: remote.port, group: group),
            clock: bridgeTicks
        )
        let rule = BridgeRule(
            filter: try #require(TopicFilter(rawValue: "printer/#")),
            direction: .outbound,
            qos: .atLeastOnce,
            localPrefix: "",
            remotePrefix: "home/"
        )
        let bridge = MQTTBridge.run(rules: [rule], local: options("bridge-local"), remote: options("bridge-remote"))
            .runReader(BridgeWorld(local: localWorld, remote: remoteWorld))

        let watched = try #require(TopicFilter(rawValue: "home/printer/+"))
        let status = try #require(TopicName(rawValue: "printer/status"))
        let subscriber = MQTTClient.session(
            options("watcher"),
            requests: [ClientRequest.subscribe([Subscription(filter: watched, options: .qos(.atLeastOnce))], properties: [])].publisher
        )
        .runReader(remoteWorld)
        // Retained, so the message reaches the remote side however the three sessions interleave.
        let message = OutgoingMessage(topic: status, payload: Array("printing".utf8), qos: .atLeastOnce, retain: true, properties: [])
        let publisher = MQTTClient.session(options("printer"), requests: [ClientRequest.publish(message)].publisher).runReader(localWorld)

        let received = await subscriber
            .compactMap { event -> String? in
                guard case let .message(publish) = event else { return nil }
                return "\(publish.topic.rawValue)=\(String(bytes: publish.payload, encoding: .utf8) ?? "")"
            }
            .merge(with: bridge.compactMap(const(String?.none)).mapError(const(ClientError.connectionClosed)))
            .merge(with: publisher.compactMap(const(String?.none)))
            .prefix(1)
            .firstResultTask()
            .run()
        #expect(received == .success("home/printer/status=printing"))
        brokers.forEach { $0.cancel() }
        try await group.shutdownGracefully()
    }
}
#endif
