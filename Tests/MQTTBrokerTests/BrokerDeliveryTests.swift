// SPDX-License-Identifier: Apache-2.0

import FP
import MQTT
import MQTTBroker
import Testing

@Suite struct BrokerQoSTests {
    @Test func inboundQoS2IsDistributedOnceAndCompleted() {
        let first = publish("t", "once", qos: .exactlyOnce, identifier: 4)
        guard case var .publish(duplicate) = first else { return }
        duplicate.duplicate = true
        let (commands, state) = run(
            join(alice, "a") + [from(alice, subscribe([subscription("t", .atMostOnce)]))]
                + join(bob, "b") + [from(bob, first), from(bob, .publish(duplicate)), from(bob, .pubRel(.success(id(4))))]
        )
        #expect(payloads(publishes(commands, to: alice)) == ["once"])
        #expect(sent(commands, to: bob) == [
            sent(commands, to: bob)[0],
            .pubRec(.success(id(4))),
            .pubRec(.success(id(4))),
            .pubComp(.success(id(4))),
        ])
        #expect(state.sessions["b"]?.receivedQoS2.isEmpty == true)
    }

    @Test func outboundQoS2Handshake() {
        let (commands, state) = run(
            join(alice, "a") + [from(alice, subscribe([subscription("t", .exactlyOnce)]))]
                + join(bob, "b") + [from(bob, publish("t", qos: .exactlyOnce))]
                + [from(alice, .pubRec(.success(id(1))))]
        )
        #expect(sent(commands, to: alice).last == .pubRel(.success(id(1))))
        #expect(state.sessions["a"]?.inFlight.first?.released == true)
        let (_, done) = run([from(alice, .pubComp(.success(id(1))))], from: state)
        #expect(done.sessions["a"]?.inFlight.isEmpty == true)
    }

    @Test func clientReceiveMaximumHoldsDeliveries() {
        let limited = connect("a", properties: [.receiveMaximum(1)])
        let (commands, state) = run(
            join(alice, "a", limited) + [from(alice, subscribe([subscription("t")]))]
                + join(bob, "b") +
                [
                    from(bob, publish("t", "1", qos: .atLeastOnce, identifier: 1)),
                    from(bob, publish("t", "2", qos: .atLeastOnce, identifier: 2)),
                ]
        )
        #expect(payloads(publishes(commands, to: alice)) == ["1"])
        let (more, _) = run([from(alice, .pubAck(.success(id(1))))], from: state)
        #expect(payloads(publishes(more, to: alice)) == ["2"])
    }

    @Test func publishAboveMaximumQoSDisconnects() {
        let options = BrokerOptions(maximumQoS: .atLeastOnce)
        let (commands, _) = run(join(alice, "a") + [from(alice, publish("t", qos: .exactlyOnce))], from: .initial(options))
        #expect(sent(commands, to: alice).last == .disconnect(Disconnect(reasonCode: .qosNotSupported, properties: [])))
    }

    @Test func subscriptionQoSIsCappedToTheBrokersMaximum() {
        let options = BrokerOptions(maximumQoS: .atLeastOnce)
        let (commands, _) = run(join(alice, "a") + [from(alice, subscribe([subscription("t", .exactlyOnce)]))], from: .initial(options))
        #expect(sent(commands, to: alice).last == .subAck(SubAck(packetIdentifier: id(1), reasonCodes: [.grantedQoS1], properties: [])))
    }

    @Test func messageExpiryDropsStaleQueuedMessages() {
        let persistent = connect("p", cleanStart: false, properties: [.sessionExpiryInterval(1_000)])
        let expiring = Publish(
            topic: topic("t"),
            payload: [1],
            delivery: .atLeastOnce(id(1)),
            retain: false,
            duplicate: false,
            properties: [.messageExpiryInterval(5)]
        )
        let (commands, _) = run(
            join(alice, "p", persistent) + [from(alice, subscribe([subscription("t")])), .connection(.closed(alice))]
                + join(bob, "b") + [from(bob, .publish(expiring)), tick(10)] + join(carol, "p", persistent)
        )
        #expect(publishes(commands, to: carol).isEmpty)
    }
}

@Suite struct BrokerWillTests {
    private let will = Will(topic: topic("clients/a"), payload: Array("gone".utf8), qos: .atMostOnce, retain: false, properties: [])

    private func watcher() -> [BrokerInput] {
        join(bob, "watcher") + [from(bob, subscribe([subscription("clients/+", .atMostOnce)]))]
    }

    @Test func willIsPublishedWhenTheClientDisappears() {
        let (commands, _) = run(watcher() + join(alice, "a", connect("a", will: will)) + [.connection(.closed(alice)), tick(0)])
        #expect(payloads(publishes(commands, to: bob)) == ["gone"])
    }

    @Test func willIsDiscardedOnAGracefulDisconnect() {
        let (commands, _) = run(watcher() + join(alice, "a", connect("a", will: will)) + [from(alice, .disconnect(.normal)), tick(0)])
        #expect(publishes(commands, to: bob).isEmpty)
    }

    @Test func disconnectWithWillMessagePublishesIt() {
        let (commands, _) = run(
            watcher() + join(alice, "a", connect("a", will: will))
                + [from(alice, .disconnect(Disconnect(reasonCode: .disconnectWithWillMessage, properties: []))), tick(0)]
        )
        #expect(payloads(publishes(commands, to: bob)) == ["gone"])
    }

    @Test func willDelayIsCancelledByReconnecting() {
        var delayed = will
        delayed.properties = [.willDelayInterval(30)]
        let persistent = connect("a", cleanStart: false, will: delayed, properties: [.sessionExpiryInterval(100)])
        let (commands, _) = run(
            watcher() + join(alice, "a", persistent) + [.connection(.closed(alice)), tick(10)]
                + join(carol, "a", connect("a", cleanStart: false, properties: [.sessionExpiryInterval(100)])) + [tick(40)]
        )
        #expect(publishes(commands, to: bob).isEmpty)
    }

    @Test func delayedWillFiresWhenTheClientStaysAway() {
        var delayed = will
        delayed.properties = [.willDelayInterval(30)]
        let persistent = connect("a", cleanStart: false, will: delayed, properties: [.sessionExpiryInterval(100)])
        let inputs = watcher() + join(alice, "a", persistent) + [.connection(.closed(alice))]
        #expect(publishes(run(inputs + [tick(29)]).0, to: bob).isEmpty)
        #expect(payloads(publishes(run(inputs + [tick(30)]).0, to: bob)) == ["gone"])
    }
}
