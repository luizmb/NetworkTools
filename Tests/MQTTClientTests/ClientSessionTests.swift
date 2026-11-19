// SPDX-License-Identifier: Apache-2.0

import Foundation
import FP
import MQTT
import MQTTClient
import ReactiveConcurrency
import Testing

// swiftlint:disable force_unwrapping
private let statusTopic = TopicName(rawValue: "elegoo/SERIAL/api_status")!
private let statusFilter = TopicFilter(rawValue: "elegoo/+/api_status")!
private let commandTopic = TopicName(rawValue: "elegoo/SERIAL/client/api_request")!
// swiftlint:enable force_unwrapping

/// An in-memory broker on the other end of a fake transport. Test-only shared state behind a lock.
private final class FakeBroker: @unchecked Sendable {
    private let lock = NSLock()
    private var stream = PacketStream(version: .v5, maximumPacketSize: 1 << 16)
    private var received: [Packet] = []
    private let outbound: AsyncStream<[UInt8]>.Continuation
    let inbound: AsyncStream<[UInt8]>
    let reply: @Sendable (Packet) -> [Packet]

    init(reply: @escaping @Sendable (Packet) -> [Packet]) {
        (inbound, outbound) = AsyncStream<[UInt8]>.makeStream()
        self.reply = reply
    }

    var packets: [Packet] { lock.withLock { received } }

    func accept(_ bytes: [UInt8]) {
        let packets: [Packet] = lock.withLock {
            let (result, next) = PacketStream.feed(bytes).runStateful(stream)
            stream = next
            let decoded = (try? result.get()) ?? []
            received += decoded
            return decoded
        }
        for packet in packets {
            let replies = reply(packet)
            replies.forEach { outbound.yield(wire($0)) }
            if replies.contains(where: { $0.type == .disconnect }) { outbound.finish() }
        }
    }

    var transport: Transport {
        Transport {
            .just(TransportConnection(
                receive: Publisher<[UInt8], TransportError> { continuation async throws(TransportError) in
                    for await chunk in self.inbound {
                        continuation.yield(chunk)
                    }
                },
                send: { bytes in
                    Publisher.future { () async -> Result<Void, TransportError> in
                        self.accept(bytes)
                        return .success(())
                    }
                },
                close: { .just(()) }
            ))
        }
    }
}

private let status = Publish(
    topic: statusTopic,
    payload: Array("{\"id\":1,\"method\":6000,\"result\":{}}".utf8),
    delivery: .atMostOnce,
    retain: false,
    duplicate: false,
    properties: []
)

private func printerLikeBroker(_ packet: Packet) -> [Packet] {
    switch packet {
    case .connect:
        [.connAck(ConnAck(sessionPresent: false, reasonCode: .success, properties: []))]
    case let .subscribe(subscribe):
        [
            .subAck(SubAck(packetIdentifier: subscribe.packetIdentifier, reasonCodes: [.grantedQoS0], properties: [])),
            .publish(status),
        ]
    case let .publish(publish):
        publish.delivery.packetIdentifier.map { [.pubAck(.success($0))] }.map {
            $0 + [.disconnect(Disconnect(reasonCode: .serverShuttingDown, properties: []))]
        } ?? []
    default:
        []
    }
}

private func world(_ transport: Transport) -> ClientWorld {
    ClientWorld(transport: transport, keepAliveTimer: const(.empty()))
}

@Suite struct ClientSessionTests {
    @Test func fullSessionAgainstAFakeBroker() async {
        let broker = FakeBroker(reply: printerLikeBroker)
        let subscriptions = [Subscription(filter: statusFilter, options: .qos(.atMostOnce))]
        let command = OutgoingMessage(
            topic: commandTopic, payload: Array("{\"type\":\"PING\"}".utf8), qos: .atLeastOnce, retain: false, properties: []
        )
        let requests: Publisher<ClientRequest, Never> =
            [ClientRequest.subscribe(subscriptions, properties: []), .publish(command)].publisher

        let result = await MQTTClient.session(options(), requests: requests)
            .runReader(world(broker.transport))
            .collect()
            .firstResultTask()
            .run()

        let events = (try? result?.get()) ?? []
        #expect(events.count == 5)
        #expect(events.first == .connected(ConnAck(sessionPresent: false, reasonCode: .success, properties: [])))
        #expect(events.contains(.subscribed(subscriptions, SubAck(packetIdentifier: .first, reasonCodes: [.grantedQoS0], properties: []))))
        #expect(events.contains(.message(status)))
        #expect(events.last == .disconnected(Disconnect(reasonCode: .serverShuttingDown, properties: []), byServer: true))
        #expect(broker.packets.first.map(\.type) == .connect)
    }

    @Test func connectionFailureIsTyped() async {
        let failing = Transport { .fail(.connectionFailed("no route")) }
        let result = await MQTTClient.session(options(), requests: .empty())
            .runReader(world(failing))
            .collect()
            .firstResultTask()
            .run()
        #expect(result == .failure(.transport(.connectionFailed("no route"))))
    }

    @Test func refusedConnectionIsTyped() async {
        let refused = ConnAck(sessionPresent: false, reasonCode: .notAuthorized, properties: [])
        let broker = FakeBroker { packet in packet.type == .connect ? [.connAck(refused)] : [] }
        let result = await MQTTClient.session(options(), requests: .empty())
            .runReader(world(broker.transport))
            .collect()
            .firstResultTask()
            .run()
        #expect(result == .failure(.connectionRefused(refused)))
    }

    @Test func requestedDisconnectFinishesTheSession() async {
        let broker = FakeBroker(reply: printerLikeBroker)
        let result = await MQTTClient.session(options(), requests: [ClientRequest.disconnect(.normal)].publisher)
            .runReader(world(broker.transport))
            .collect()
            .firstResultTask()
            .run()
        #expect(result == .success([
            .connected(ConnAck(sessionPresent: false, reasonCode: .success, properties: [])),
            .disconnected(.normal, byServer: false),
        ]))
        #expect(broker.packets.map(\.type) == [.connect, .disconnect])
    }
}
