// SPDX-License-Identifier: Apache-2.0

import FP
import MQTT
import MQTTBroker
import Testing

@Suite struct BrokerRoutingTests {
    @Test func deliversToMatchingSubscribers() {
        let (commands, _) = run(
            join(alice, "a") + [from(alice, subscribe([subscription("sensors/+")]))]
                + join(bob, "b") + [from(bob, publish("sensors/temp", "21", qos: .atLeastOnce, identifier: 7))]
        )
        #expect(sent(commands, to: bob).last == .pubAck(.success(id(7))))
        let delivered = publishes(commands, to: alice)
        #expect(payloads(delivered) == ["21"])
        #expect(delivered.first?.delivery == .atLeastOnce(id(1)))
    }

    @Test func qosIsCappedByTheSubscription() {
        let (commands, _) = run(
            join(alice, "a") + [from(alice, subscribe([subscription("t", .atMostOnce)]))]
                + join(bob, "b") + [from(bob, publish("t", qos: .exactlyOnce))]
        )
        #expect(publishes(commands, to: alice).map(\.delivery) == [.atMostOnce])
    }

    @Test func overlappingSubscriptionsDeliverOnceWithAllIdentifiers() {
        let (commands, _) = run(
            join(alice, "a")
                + [from(alice, subscribe([subscription("a/+", .atMostOnce)], identifier: 1, properties: [.subscriptionIdentifier(5)]))]
                + [from(alice, subscribe([subscription("a/#", .atLeastOnce)], identifier: 2, properties: [.subscriptionIdentifier(9)]))]
                + join(bob, "b") + [from(bob, publish("a/b", qos: .exactlyOnce))]
        )
        let delivered = publishes(commands, to: alice)
        #expect(delivered.count == 1)
        #expect(delivered.first?.delivery.qos == .atLeastOnce)
        #expect(delivered.first?.properties == [.subscriptionIdentifier(5), .subscriptionIdentifier(9)])
    }

    @Test func noLocalSkipsTheClientsOwnMessages() {
        let local = Subscription(
            filter: filter("t"),
            options: SubscriptionOptions(qos: .atMostOnce, noLocal: true, retainAsPublished: false, retainHandling: .sendOnSubscribe)
        )
        let (commands, _) = run(join(alice, "a") + [from(alice, subscribe([local])), from(alice, publish("t"))])
        #expect(publishes(commands, to: alice).isEmpty)
    }

    @Test func retainedMessagesReachLaterSubscribers() {
        let (commands, _) = run(
            join(bob, "b") + [from(bob, publish("status", "online", retain: true))]
                + join(alice, "a") + [from(alice, subscribe([subscription("status")]))]
        )
        let delivered = publishes(commands, to: alice)
        #expect(payloads(delivered) == ["online"])
        #expect(delivered.first?.retain == true)
    }

    @Test func emptyRetainedPayloadClearsIt() {
        let (_, state) = run(
            join(bob, "b") + [from(bob, publish("status", "online", retain: true)), from(bob, publish("status", "", retain: true))]
        )
        #expect(state.retained.isEmpty)
    }

    @Test func retainHandlingDoNotSend() {
        let quiet = Subscription(
            filter: filter("status"),
            options: SubscriptionOptions(qos: .atMostOnce, noLocal: false, retainAsPublished: false, retainHandling: .doNotSend)
        )
        let (commands, _) = run(
            join(bob, "b") + [from(bob, publish("status", "online", retain: true))] + join(alice, "a") + [from(alice, subscribe([quiet]))]
        )
        #expect(publishes(commands, to: alice).isEmpty)
    }

    @Test func forwardedMessagesClearRetainUnlessRetainAsPublished() {
        let (commands, _) = run(
            join(alice, "a") + [from(alice, subscribe([subscription("t", .atMostOnce)]))]
                + join(bob, "b") + [from(bob, publish("t", retain: true))]
        )
        #expect(publishes(commands, to: alice).map(\.retain) == [false])
    }

    @Test func sharedSubscriptionsRoundRobin() {
        let shared = [subscription("$share/workers/jobs", .atMostOnce)]
        let (commands, _) = run(
            join(alice, "a") + [from(alice, subscribe(shared))] + join(carol, "c") + [from(carol, subscribe(shared))]
                + join(bob, "b") + [from(bob, publish("jobs", "1")), from(bob, publish("jobs", "2"))]
        )
        #expect(payloads(publishes(commands, to: alice)) == ["1"])
        #expect(payloads(publishes(commands, to: carol)) == ["2"])
    }

    @Test func unauthorizedPublishIsRefusedAndNotDistributed() {
        let readOnly = BrokerPolicy(
            authenticate: const(.success),
            mayPublish: { client, _ in client != "b" },
            maySubscribe: { _, _ in true }
        )
        let (commands, _) = run(
            join(alice, "a") + [from(alice, subscribe([subscription("t")]))]
                + join(bob, "b") + [from(bob, publish("t", qos: .atLeastOnce))],
            policy: readOnly
        )
        let refused = Acknowledgement(packetIdentifier: id(1), reasonCode: .notAuthorized, properties: [])
        #expect(sent(commands, to: bob).last == .pubAck(refused))
        #expect(publishes(commands, to: alice).isEmpty)
    }

    @Test func clientTopicAliases() {
        let aliased = Publish(
            topic: topic("long/topic"),
            payload: [1],
            delivery: .atMostOnce,
            retain: false,
            duplicate: false,
            properties: [.topicAlias(1)]
        )
        var short = aliased
        short.topic = TopicName(rawValue: "") ?? aliased.topic
        let (commands, _) = run(
            join(alice, "a") + [from(alice, subscribe([subscription("long/topic", .atMostOnce)]))]
                + join(bob, "b") + [from(bob, .publish(aliased)), from(bob, .publish(short))]
        )
        #expect(publishes(commands, to: alice).map(\.topic.rawValue) == ["long/topic", "long/topic"])
    }

    @Test func unsubscribeReportsMissingSubscriptions() {
        let (commands, _) = run(
            join(alice, "a") + [
                from(alice, subscribe([subscription("t")])),
                from(alice, .unsubscribe(Unsubscribe(packetIdentifier: id(2), filters: [filter("t"), filter("u")], properties: []))),
            ]
        )
        #expect(sent(commands, to: alice).last == .unsubAck(UnsubAck(
            packetIdentifier: id(2),
            reasonCodes: [.success, .noSubscriptionExisted],
            properties: []
        )))
    }
}
