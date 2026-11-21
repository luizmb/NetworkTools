// SPDX-License-Identifier: Apache-2.0

import FP
import MQTT
import MQTTClient
import Testing

private func incomingPublish(_ delivery: Delivery) -> Publish {
    Publish(topic: topic("t"), payload: [], delivery: delivery, retain: false, duplicate: false, properties: [])
}

@Suite struct ClientPublishTests {
    @Test func qos1RoundTrip() {
        let (commands, state) = run([request(.publish(message(.atLeastOnce)))], from: connected())
        guard let publish = publishes(commands).first, let identifier = publish.delivery.packetIdentifier else {
            Issue.record("expected a QoS 1 PUBLISH")
            return
        }
        let (acked, final) = run([rx(.pubAck(.success(identifier)))], from: state)
        #expect(acked == [.emit(.published(publish, .success(identifier)))])
        #expect(final.inFlight.isEmpty)
    }

    @Test func qos2RoundTrip() {
        let (commands, state) = run([request(.publish(message(.exactlyOnce)))], from: connected())
        guard let publish = publishes(commands).first, let identifier = publish.delivery.packetIdentifier else {
            Issue.record("expected a QoS 2 PUBLISH")
            return
        }
        let (released, waiting) = run([rx(.pubRec(.success(identifier)))], from: state)
        #expect(sent(released) == [.pubRel(.success(identifier))])
        let (completed, final) = run([rx(.pubComp(.success(identifier)))], from: waiting)
        #expect(completed == [.emit(.published(publish, .success(identifier)))])
        #expect(final.inFlight.isEmpty)
    }

    @Test func qos2RejectedByPubRec() {
        let (commands, state) = run([request(.publish(message(.exactlyOnce)))], from: connected())
        guard let publish = publishes(commands).first, let identifier = publish.delivery.packetIdentifier else {
            Issue.record("expected a QoS 2 PUBLISH")
            return
        }
        let rejection = Acknowledgement(packetIdentifier: identifier, reasonCode: .quotaExceeded, properties: [])
        #expect(run([rx(.pubRec(rejection))], from: state).0 == [.emit(.published(publish, rejection))])
    }

    @Test func identifiersAreDistinctWhileInFlight() {
        let (commands, _) = run([request(.publish(message(.atLeastOnce))), request(.publish(message(.atLeastOnce)))], from: connected())
        #expect(publishes(commands).compactMap(\.delivery.packetIdentifier) == [id(1), id(2)])
    }

    @Test func unknownAcknowledgementIsAViolation() {
        #expect(run([rx(.pubAck(.success(id(99))))], from: connected()).0.last == .fail(.protocolViolation(.unknownPacketIdentifier(
            .pubAck,
            id(99)
        ))))
    }

    @Test func incomingQoS1IsAcknowledged() {
        let incoming = incomingPublish(.atLeastOnce(id(5)))
        #expect(run([rx(.publish(incoming))], from: connected()).0 == [.emit(.message(incoming)), .send(c1, .pubAck(.success(id(5))), .v5)])
    }

    @Test func incomingQoS2IsDeliveredOnce() {
        let incoming = incomingPublish(.exactlyOnce(id(6)))
        var duplicate = incoming
        duplicate.duplicate = true
        let (commands, state) = run([rx(.publish(incoming)), rx(.publish(duplicate)), rx(.pubRel(.success(id(6))))], from: connected())
        #expect(events(commands) == [.message(incoming)])
        #expect(sent(commands) == [.pubRec(.success(id(6))), .pubRec(.success(id(6))), .pubComp(.success(id(6)))])
        #expect(state.receivedQoS2.isEmpty)
    }

    @Test func unknownPubRelStillCompletes() {
        let notFound = Acknowledgement(packetIdentifier: id(8), reasonCode: .packetIdentifierNotFound, properties: [])
        #expect(sent(run([rx(.pubRel(.success(id(8))))], from: connected()).0) == [.pubComp(notFound)])
    }
}

@Suite struct ClientSubscriptionTests {
    private let subscriptions = [Subscription(filter: filter("elegoo/#"), options: .qos(.atMostOnce))]

    @Test func subscribeAndAck() {
        let (commands, state) = run([request(.subscribe(subscriptions, properties: []))], from: connected())
        #expect(sent(commands) == [.subscribe(Subscribe(packetIdentifier: id(1), subscriptions: subscriptions, properties: []))])
        let ack = SubAck(packetIdentifier: id(1), reasonCodes: [.grantedQoS0], properties: [])
        let (acked, final) = run([rx(.subAck(ack))], from: state)
        #expect(acked == [.emit(.subscribed(subscriptions, ack))])
        #expect(final.subscriptions == subscriptions)
    }

    @Test func refusedSubscriptionsAreNotRemembered() {
        let ack = SubAck(packetIdentifier: id(1), reasonCodes: [.notAuthorized], properties: [])
        let (_, state) = run([request(.subscribe(subscriptions, properties: [])), rx(.subAck(ack))], from: connected())
        #expect(state.subscriptions.isEmpty)
    }

    @Test func unsubscribeForgetsTheSubscription() {
        let ack = SubAck(packetIdentifier: id(1), reasonCodes: [.grantedQoS0], properties: [])
        let unsubAck = UnsubAck(packetIdentifier: id(2), reasonCodes: [.success], properties: [])
        let (commands, state) = run(
            [
                request(.subscribe(subscriptions, properties: [])),
                rx(.subAck(ack)),
                request(.unsubscribe([filter("elegoo/#")], properties: [])),
                rx(.unsubAck(unsubAck))
            ],
            from: connected()
        )
        #expect(events(commands).last == .unsubscribed([filter("elegoo/#")], unsubAck))
        #expect(state.subscriptions.isEmpty)
    }
}
