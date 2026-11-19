// SPDX-License-Identifier: Apache-2.0

import FP
import MQTT
import MQTTClient
import Testing

// swiftlint:disable force_unwrapping
private func topic(_ value: String) -> TopicName { TopicName(rawValue: value)! }
private func filter(_ value: String) -> TopicFilter { TopicFilter(rawValue: value)! }
private func id(_ value: UInt16) -> PacketIdentifier { PacketIdentifier(rawValue: value)! }
// swiftlint:enable force_unwrapping

func options(_ version: ProtocolVersion = .v5, keepAlive: UInt16 = 30) -> ClientOptions {
    ClientOptions(
        version: version,
        clientIdentifier: "test",
        cleanStart: true,
        keepAlive: keepAlive,
        will: nil,
        userName: "elegoo",
        password: Array("code".utf8),
        properties: [],
        maximumPacketSize: 1 << 16
    )
}

func wire(_ packet: Packet, _ version: ProtocolVersion = .v5) -> [UInt8] {
    (try? packet.encode(for: version).get()) ?? []
}

/// Runs inputs through the machine, returning every output and the final state.
func run(_ inputs: [ClientInput], from state: ClientState) -> ([ClientOutput], ClientState) {
    inputs.reduce(([ClientOutput](), state)) { acc, input in
        let (outputs, next) = ClientMachine.step(input).runStateful(acc.1)
        return (acc.0 + outputs, next)
    }
}

let accepted = ConnAck(sessionPresent: false, reasonCode: .success, properties: [])

/// A state that has completed the handshake.
func connected(_ version: ProtocolVersion = .v5) -> ClientState {
    run([.start, .received(wire(.connAck(accepted), version))], from: .initial(options(version))).1
}

private func message(_ qos: QoS) -> OutgoingMessage {
    OutgoingMessage(topic: topic("a/b"), payload: [1], qos: qos, retain: false, properties: [])
}

@Suite struct ClientHandshakeTests {
    @Test func startSendsConnect() {
        let (outputs, state) = run([.start], from: .initial(options()))
        #expect(outputs == [.send(.connect(options().connect))])
        #expect(state.phase == .connecting)
    }

    @Test func connAckConnects() {
        let (outputs, state) = run([.start, .received(wire(.connAck(accepted)))], from: .initial(options()))
        #expect(outputs.last == .event(.connected(accepted)))
        #expect(state.phase == .connected)
    }

    @Test func refusedConnAckFails() {
        let refused = ConnAck(sessionPresent: false, reasonCode: .notAuthorized, properties: [])
        let (outputs, state) = run([.start, .received(wire(.connAck(refused)))], from: .initial(options()))
        #expect(outputs.last == .fail(.connectionRefused(refused)))
        #expect(state.phase == .closed)
    }

    @Test func requestsBeforeConnAckAreQueuedThenSent() {
        let (outputs, _) = run(
            [.start, .request(.publish(message(.atMostOnce))), .received(wire(.connAck(accepted)))],
            from: .initial(options())
        )
        #expect(outputs.count == 3)
        #expect(outputs[1] == .event(.connected(accepted)))
        #expect(outputs[2] == .send(.publish(Publish(
            topic: topic("a/b"),
            payload: [1],
            delivery: .atMostOnce,
            retain: false,
            duplicate: false,
            properties: []
        ))))
    }

    @Test func packetBeforeConnAckIsAViolation() {
        let (outputs, state) = run([.start, .received(wire(.pingResp))], from: .initial(options()))
        #expect(outputs.suffix(2) == [
            .send(.disconnect(Disconnect(reasonCode: .protocolError, properties: []))),
            .fail(.protocolViolation(.unexpectedPacket(.pingResp))),
        ])
        #expect(state.phase == .closed)
    }

    @Test func violationIn311DoesNotSendDisconnect() {
        let (outputs, _) = run([.start, .received(wire(.pingResp, .v3_1_1))], from: .initial(options(.v3_1_1)))
        #expect(outputs.last == .fail(.protocolViolation(.unexpectedPacket(.pingResp))))
        #expect(!outputs.contains(.send(.disconnect(Disconnect(reasonCode: .protocolError, properties: [])))))
    }

    @Test func connAckSplitAcrossChunks() {
        let bytes = wire(.connAck(accepted))
        let (outputs, state) = run(
            [.start] + bytes.map { .received([$0]) },
            from: .initial(options())
        )
        #expect(outputs.last == .event(.connected(accepted)))
        #expect(state.phase == .connected)
    }

    @Test func malformedBytesAbort() {
        let (outputs, _) = run([.start, .received([0x00, 0x00])], from: .initial(options()))
        #expect(outputs.last == .fail(.decoding(.decoding(.reservedPacketType(0)))))
    }
}

@Suite struct ClientKeepAliveTests {
    @Test func tickSendsPing() {
        #expect(run([.keepAliveTick], from: connected()).0 == [.send(.pingReq)])
    }

    @Test func pongClearsThePing() {
        let (outputs, state) = run([.keepAliveTick, .received(wire(.pingResp)), .keepAliveTick], from: connected())
        #expect(outputs == [.send(.pingReq), .send(.pingReq)])
        #expect(state.phase == .connected)
    }

    @Test func missingPongTimesOut() {
        let (outputs, state) = run([.keepAliveTick, .keepAliveTick], from: connected())
        #expect(outputs.last == .fail(.keepAliveTimeout))
        #expect(state.phase == .closed)
    }

    @Test func missingConnAckTimesOut() {
        let (outputs, _) = run([.start, .keepAliveTick, .keepAliveTick], from: .initial(options()))
        #expect(outputs.last == .fail(.keepAliveTimeout))
    }
}

@Suite struct ClientPublishTests {
    @Test func qos1RoundTrip() {
        let (sent, state) = run([.request(.publish(message(.atLeastOnce)))], from: connected())
        guard case let .send(.publish(publish)) = sent.first, let identifier = publish.delivery.packetIdentifier else {
            Issue.record("expected a QoS 1 PUBLISH, got \(sent)")
            return
        }
        let (acked, final) = run([.received(wire(.pubAck(.success(identifier))))], from: state)
        #expect(acked == [.event(.published(publish, .success(identifier)))])
        #expect(final.inFlight.isEmpty)
    }

    @Test func qos2RoundTrip() {
        let (sent, state) = run([.request(.publish(message(.exactlyOnce)))], from: connected())
        guard case let .send(.publish(publish)) = sent.first, let identifier = publish.delivery.packetIdentifier else {
            Issue.record("expected a QoS 2 PUBLISH, got \(sent)")
            return
        }
        let (released, waiting) = run([.received(wire(.pubRec(.success(identifier))))], from: state)
        #expect(released == [.send(.pubRel(.success(identifier)))])
        let (completed, final) = run([.received(wire(.pubComp(.success(identifier))))], from: waiting)
        #expect(completed == [.event(.published(publish, .success(identifier)))])
        #expect(final.inFlight.isEmpty)
    }

    @Test func qos2RejectedByPubRec() {
        let (sent, state) = run([.request(.publish(message(.exactlyOnce)))], from: connected())
        guard case let .send(.publish(publish)) = sent.first, let identifier = publish.delivery.packetIdentifier else {
            Issue.record("expected a QoS 2 PUBLISH")
            return
        }
        let rejection = Acknowledgement(packetIdentifier: identifier, reasonCode: .quotaExceeded, properties: [])
        let (outputs, final) = run([.received(wire(.pubRec(rejection)))], from: state)
        #expect(outputs == [.event(.published(publish, rejection))])
        #expect(final.inFlight.isEmpty)
    }

    @Test func identifiersAreDistinctWhileInFlight() {
        let (sent, _) = run(
            [.request(.publish(message(.atLeastOnce))), .request(.publish(message(.atLeastOnce)))],
            from: connected()
        )
        let identifiers = sent.compactMap { output -> PacketIdentifier? in
            guard case let .send(.publish(publish)) = output else { return nil }
            return publish.delivery.packetIdentifier
        }
        #expect(identifiers == [id(1), id(2)])
    }

    @Test func unknownAcknowledgementIsAViolation() {
        let (outputs, _) = run([.received(wire(.pubAck(.success(id(99)))))], from: connected())
        #expect(outputs.last == .fail(.protocolViolation(.unknownPacketIdentifier(.pubAck, id(99)))))
    }

    @Test func incomingQoS1IsAcknowledged() {
        let incoming = Publish(
            topic: topic("t"), payload: [], delivery: .atLeastOnce(id(5)), retain: false, duplicate: false, properties: []
        )
        let (outputs, _) = run([.received(wire(.publish(incoming)))], from: connected())
        #expect(outputs == [.event(.message(incoming)), .send(.pubAck(.success(id(5))))])
    }

    @Test func incomingQoS2IsDeliveredOnce() {
        let incoming = Publish(
            topic: topic("t"), payload: [], delivery: .exactlyOnce(id(6)), retain: false, duplicate: false, properties: []
        )
        var duplicate = incoming
        duplicate.duplicate = true
        let (outputs, state) = run(
            [.received(wire(.publish(incoming))), .received(wire(.publish(duplicate))), .received(wire(.pubRel(.success(id(6)))))],
            from: connected()
        )
        #expect(outputs == [
            .event(.message(incoming)),
            .send(.pubRec(.success(id(6)))),
            .send(.pubRec(.success(id(6)))),
            .send(.pubComp(.success(id(6)))),
        ])
        #expect(state.receivedQoS2.isEmpty)
    }

    @Test func unknownPubRelStillCompletes() {
        let (outputs, _) = run([.received(wire(.pubRel(.success(id(8)))))], from: connected())
        let notFound = Acknowledgement(packetIdentifier: id(8), reasonCode: .packetIdentifierNotFound, properties: [])
        #expect(outputs == [.send(.pubComp(notFound))])
    }
}

@Suite struct ClientSubscriptionTests {
    @Test func subscribeAndAck() {
        let subscriptions = [Subscription(filter: filter("elegoo/#"), options: .qos(.atMostOnce))]
        let (sent, state) = run([.request(.subscribe(subscriptions, properties: []))], from: connected())
        #expect(sent == [.send(.subscribe(Subscribe(packetIdentifier: id(1), subscriptions: subscriptions, properties: [])))])
        let ack = SubAck(packetIdentifier: id(1), reasonCodes: [.grantedQoS0], properties: [])
        let (events, final) = run([.received(wire(.subAck(ack)))], from: state)
        #expect(events == [.event(.subscribed(subscriptions, ack))])
        #expect(final.inFlight.isEmpty)
    }

    @Test func unsubscribeAndAck() {
        let filters = [filter("a/#")]
        let (_, state) = run([.request(.unsubscribe(filters, properties: []))], from: connected())
        let ack = UnsubAck(packetIdentifier: id(1), reasonCodes: [.success], properties: [])
        let (events, _) = run([.received(wire(.unsubAck(ack)))], from: state)
        #expect(events == [.event(.unsubscribed(filters, ack))])
    }
}

@Suite struct ClientDisconnectTests {
    @Test func requestedDisconnect() {
        let (outputs, state) = run([.request(.disconnect(.normal))], from: connected())
        #expect(outputs == [.send(.disconnect(.normal)), .event(.disconnected(.normal, byServer: false)), .close])
        #expect(state.phase == .closed)
    }

    @Test func serverDisconnect() {
        let notice = Disconnect(reasonCode: .serverShuttingDown, properties: [])
        let (outputs, _) = run([.received(wire(.disconnect(notice)))], from: connected())
        #expect(outputs == [.event(.disconnected(notice, byServer: true)), .close])
    }

    @Test func transportClosedFails() {
        #expect(run([.transportClosed], from: connected()).0 == [.fail(.connectionClosed)])
    }

    @Test func nothingHappensOnceClosed() {
        let (_, closed) = run([.request(.disconnect(.normal))], from: connected())
        #expect(run([.keepAliveTick, .transportClosed, .received(wire(.pingResp))], from: closed).0.isEmpty)
    }
}
