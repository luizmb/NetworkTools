// SPDX-License-Identifier: Apache-2.0

import FP
import MQTT
import MQTTClient
import Testing

private func limitedBy(_ properties: [Property], _ clientOptions: ClientOptions = options()) -> ClientState {
    connected(clientOptions, ack: ConnAck(sessionPresent: false, reasonCode: .success, properties: properties))
}

@Suite struct ClientServerLimitsTests {
    @Test func receiveMaximumHoldsPublishesUntilASlotFrees() {
        let (first, waiting) = run(
            [request(.publish(message(.atLeastOnce, topic: "one"))), request(.publish(message(.atLeastOnce, topic: "two")))],
            from: limitedBy([.receiveMaximum(1)])
        )
        #expect(publishes(first).map(\.topic) == [topic("one")])
        #expect(waiting.queued.count == 1)
        let (second, _) = run([rx(.pubAck(.success(id(1))))], from: waiting)
        #expect(publishes(second).map(\.topic) == [topic("two")])
    }

    @Test func qosAboveTheServersMaximumIsRejected() {
        let commands = run([request(.publish(message(.exactlyOnce)))], from: limitedBy([.maximumQoS(1)])).0
        #expect(commands == [.emit(.rejected(.publish(message(.exactlyOnce)), .qosNotSupported(maximum: .atLeastOnce)))])
    }

    @Test func retainWithoutRetainAvailableIsRejected() {
        var retained = message(.atMostOnce)
        retained.retain = true
        let commands = run([request(.publish(retained))], from: limitedBy([.retainAvailable(0)])).0
        #expect(commands == [.emit(.rejected(.publish(retained), .retainNotSupported))])
    }

    @Test func wildcardSubscriptionsWithoutSupportAreRejected() {
        let subscriptions = [Subscription(filter: filter("a/+"), options: .qos(.atMostOnce))]
        #expect(
            run([request(.subscribe(subscriptions, properties: []))], from: limitedBy([.wildcardSubscriptionAvailable(0)])).0
                == [.emit(.rejected(.subscribe(subscriptions, properties: []), .wildcardSubscriptionsNotSupported))]
        )
    }

    @Test func packetsAboveTheServersMaximumSizeAreRejected() {
        var large = message(.atMostOnce)
        large.payload = Array(repeating: 0, count: 100)
        #expect(
            run([request(.publish(large))], from: limitedBy([.maximumPacketSize(64)])).0
                == [.emit(.rejected(.publish(large), .packetTooLarge(size: 108, maximum: 64)))]
        )
    }

    @Test func outgoingTopicAliasesReplaceRepeatedTopics() {
        let (commands, _) = run(
            [request(.publish(message(.atMostOnce))), request(.publish(message(.atMostOnce)))],
            from: limitedBy([.topicAliasMaximum(2)])
        )
        let sentPublishes = publishes(commands)
        #expect(sentPublishes.map(\.topic.rawValue) == ["a/b", ""])
        #expect(sentPublishes.map(\.properties) == [[.topicAlias(1)], [.topicAlias(1)]])
    }
}

@Suite struct ClientOwnLimitsTests {
    private let aliasing = options(properties: [.topicAliasMaximum(5)])

    private func incoming(_ name: String, alias: UInt16?, qos: Delivery = .atMostOnce) -> Publish {
        Publish(
            topic: TopicName(rawValue: name) ?? topic("x"),
            payload: [],
            delivery: qos,
            retain: false,
            duplicate: false,
            properties: alias.map { [.topicAlias($0)] } ?? []
        )
    }

    @Test func incomingTopicAliasesAreResolved() {
        let (commands, _) = run(
            [rx(.publish(incoming("a/b", alias: 1))), rx(.publish(incoming("", alias: 1)))],
            from: connected(aliasing)
        )
        #expect(events(commands).map { event -> String in
            guard case let .message(publish) = event else { return "?" }
            return publish.topic.rawValue
        } == ["a/b", "a/b"])
    }

    @Test func undefinedTopicAliasIsAViolation() {
        let commands = run([rx(.publish(incoming("", alias: 3)))], from: connected(aliasing)).0
        #expect(commands.first == .send(c1, .disconnect(Disconnect(reasonCode: .topicAliasInvalid, properties: [])), .v5))
        #expect(commands.last == .fail(.protocolViolation(.topicAliasInvalid(3))))
    }

    @Test func aliasesAboveThisClientsMaximumAreAViolation() {
        #expect(run([rx(.publish(incoming("a", alias: 1)))], from: connected()).0.last == .fail(.protocolViolation(.topicAliasInvalid(1))))
    }

    @Test func tooManyUnreleasedQoS2MessagesExceedTheReceiveMaximum() {
        let (commands, _) = run(
            [
                rx(.publish(incoming("a", alias: nil, qos: .exactlyOnce(id(1))))),
                rx(.publish(incoming("a", alias: nil, qos: .exactlyOnce(id(2))))),
            ],
            from: connected(options(properties: [.receiveMaximum(1)]))
        )
        #expect(commands.last == .fail(.protocolViolation(.receiveMaximumExceeded)))
    }
}
