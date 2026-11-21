// SPDX-License-Identifier: Apache-2.0

import FP
import MQTT
import MQTTClient
import Testing

@Suite struct ClientReconnectTests {
    private let subscriptions = [Subscription(filter: filter("elegoo/+/api_status"), options: .qos(.atMostOnce))]

    @Test func reconnectsAfterTheBackoffDelay() {
        let (lost, waiting) = run([tick(10), .connection(.closed(c1))], from: connected(options(reconnect: backoff)))
        #expect(lost == [.close(c1), .emit(.connectionLost(.connectionClosed, retryingIn: .seconds(1)))])
        #expect(run([tick(10)], from: waiting).0.isEmpty)
        #expect(run([tick(11)], from: waiting).0 == [.open(c2)])
    }

    @Test func backoffDoublesThenGivesUp() {
        let failure = TransportError.connectionFailed("refused")
        let (commands, state) = run(
            [
                .connection(.closed(c1)), tick(1),
                .connection(.openFailed(c2, failure)), tick(3),
                .connection(.openFailed(.outgoing(3), failure)), tick(7),
                .connection(.openFailed(.outgoing(4), failure)),
            ],
            from: connected(options(reconnect: backoff))
        )
        #expect(events(commands) == [
            .connectionLost(.connectionClosed, retryingIn: .seconds(1)),
            .connectionLost(.transport(failure), retryingIn: .seconds(2)),
            .connectionLost(.transport(failure), retryingIn: .seconds(4)),
        ])
        #expect(commands.last == .fail(.transport(failure)))
        #expect(state.phase == .closed)
    }

    @Test func requestsWhileReconnectingAreSentAfterConnAck() {
        let (commands, _) = run(
            [
                .connection(.closed(c1)), request(.publish(message(.atMostOnce))),
                tick(1), .connection(.opened(c2)), rx(.connAck(accepted), on: c2),
            ],
            from: connected(options(reconnect: backoff))
        )
        #expect(publishes(commands).count == 1)
    }

    @Test func resubscribesWhenTheServerLostTheSession() {
        let ack = SubAck(packetIdentifier: id(1), reasonCodes: [.grantedQoS0], properties: [])
        let (commands, _) = run(
            [
                request(.subscribe(subscriptions, properties: [])), rx(.subAck(ack)),
                .connection(.closed(c1)), tick(1), .connection(.opened(c2)), rx(.connAck(accepted), on: c2),
            ],
            from: connected(options(reconnect: backoff))
        )
        #expect(sent(commands).last == .subscribe(Subscribe(packetIdentifier: id(2), subscriptions: subscriptions, properties: [])))
    }

    @Test func resumedSessionResendsInFlightAsDuplicatesInOrder() {
        let resumed = ConnAck(sessionPresent: true, reasonCode: .success, properties: [])
        let persistent = options(cleanStart: false, reconnect: backoff)
        let (commands, _) = run(
            [
                request(.publish(message(.exactlyOnce, topic: "first"))), rx(.pubRec(.success(id(1)))),
                request(.publish(message(.atLeastOnce, topic: "second"))),
                .connection(.closed(c1)), tick(1), .connection(.opened(c2)), rx(.connAck(resumed), on: c2),
            ],
            from: connected(persistent)
        )
        let afterReconnect = Array(sent(commands).drop { if case .connect = $0 { false } else { true } }.dropFirst())
        #expect(afterReconnect.count == 2)
        #expect(afterReconnect.first == .pubRel(.success(id(1))))
        guard case let .publish(publish)? = afterReconnect.last else {
            Issue.record("expected the QoS 1 PUBLISH to be resent")
            return
        }
        #expect(publish.duplicate)
        #expect(publish.delivery == .atLeastOnce(id(2)))
    }

    @Test func lostSessionCompletesReleasedMessagesAndResendsTheRest() {
        let (commands, state) = run(
            [
                request(.publish(message(.exactlyOnce, topic: "first"))), rx(.pubRec(.success(id(1)))),
                request(.publish(message(.atLeastOnce, topic: "second"))),
                .connection(.closed(c1)), tick(1), .connection(.opened(c2)), rx(.connAck(accepted), on: c2),
            ],
            from: connected(options(reconnect: backoff))
        )
        #expect(events(commands).contains { if case .published = $0 { true } else { false } })
        #expect(publishes(commands).last.map { !$0.duplicate && $0.delivery == .atLeastOnce(id(2)) } == true)
        #expect(state.inFlight.map(\.identifier) == [id(2)])
    }
}
