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
    let dropAfterConnAck: Bool

    init(dropAfterConnAck: Bool = false, reply: @escaping @Sendable (Packet) -> [Packet]) {
        (inbound, outbound) = AsyncStream<[UInt8]>.makeStream()
        self.reply = reply
        self.dropAfterConnAck = dropAfterConnAck
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
            if replies.contains(where: { $0.type == .disconnect }) || (dropAfterConnAck && packet.type == .connect) {
                outbound.finish()
            }
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

/// A transport whose first connection drops right after CONNACK; later ones behave. Test-only.
private final class FlakyNetwork: @unchecked Sendable {
    private let lock = NSLock()
    private var connections = 0

    var transport: Transport {
        Transport {
            let attempt = self.lock.withLock {
                self.connections += 1
                return self.connections
            }
            return FakeBroker(dropAfterConnAck: attempt == 1, reply: printerLikeBroker).transport.connect()
        }
    }
}

private func world(_ transport: Transport) -> ClientWorld {
    ClientWorld(transport: transport, clock: const(.empty()))
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

    @Test func reconnectsAndResubscribesAfterADrop() async {
        let reconnecting = options(reconnect: .exponentialBackoff(initial: .milliseconds(50), maximum: .seconds(1), attempts: 5))
        let subscriptions = [Subscription(filter: statusFilter, options: .qos(.atMostOnce))]
        let clockWorld = ClientWorld(
            transport: FlakyNetwork().transport,
            clock: { .monotonicTicks(every: .milliseconds(10), clock: ContinuousClock()) }
        )
        let result = await MQTTClient.session(reconnecting, requests: [ClientRequest.subscribe(subscriptions, properties: [])].publisher)
            .runReader(clockWorld)
            .prefix { event in
                if case .message = event { false } else { true }
            }
            .collect()
            .firstResultTask()
            .run()

        let received = (try? result?.get()) ?? []
        #expect(received.first == .connected(accepted))
        #expect(received.contains(.connectionLost(.connectionClosed, retryingIn: .milliseconds(50))))
        #expect(received.filter { $0 == .connected(accepted) }.count == 2)
        #expect(received.last.map { if case .subscribed = $0 { true } else { false } } == true)
    }

    @Test func followsARedirectThroughTheWorld() async {
        let moved = ConnAck(sessionPresent: false, reasonCode: .serverMoved, properties: [.serverReference("elsewhere")])
        let original = FakeBroker { packet in packet.type == .connect ? [.connAck(moved)] : [] }
        let elsewhere = FakeBroker(reply: printerLikeBroker)
        let world = ClientWorld(
            transport: original.transport,
            clock: const(.empty()),
            redirect: { reference in reference == "elsewhere" ? elsewhere.transport : nil }
        )
        let result = await MQTTClient.session(options(), requests: [ClientRequest.disconnect(.normal)].publisher)
            .runReader(world)
            .collect()
            .firstResultTask()
            .run()
        #expect(result == .success([
            .redirected(to: "elsewhere", permanent: true),
            .connected(ConnAck(sessionPresent: false, reasonCode: .success, properties: [])),
            .disconnected(.normal, byServer: false),
        ]))
    }
}
