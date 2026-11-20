// SPDX-License-Identifier: Apache-2.0

import FP
import MQTT
import MQTTBroker
import Testing

@Suite struct BrokerConnectTests {
    @Test func acceptsAndAnnouncesItsLimits() {
        let (commands, _) = run(join(alice, "a"))
        let expected = ConnAck(
            sessionPresent: false,
            reasonCode: .success,
            properties: [.receiveMaximum(100), .maximumPacketSize(1 << 20), .topicAliasMaximum(10)]
        )
        #expect(sent(commands, to: alice) == [.connAck(expected)])
        #expect(commands.contains(.emit(.clientConnected(clientIdentifier: "a", alice, resumed: false))))
    }

    @Test func mqtt311GetsAPlainConnAck() {
        let (commands, _) = run([open(alice), from(alice, connect("a", version: .v3_1_1), .v3_1_1)])
        #expect(sent(commands, to: alice) == [.connAck(ConnAck(sessionPresent: false, reasonCode: .success, properties: []))])
    }

    @Test func policyRefusal() {
        let strict = BrokerPolicy(authenticate: const(.badUserNameOrPassword), mayPublish: { _, _ in true }, maySubscribe: { _, _ in true })
        let (commands, state) = run(join(alice, "a"), policy: strict)
        #expect(sent(commands, to: alice) == [.connAck(ConnAck(sessionPresent: false, reasonCode: .badUserNameOrPassword, properties: []))])
        #expect(closes(commands) == [alice])
        #expect(state.sessions.isEmpty)
    }

    @Test func assignsAnIdentifierWhenEmpty() {
        let (commands, state) = run(join(alice, ""))
        guard case let .connAck(ack)? = sent(commands, to: alice).first else {
            Issue.record("expected CONNACK")
            return
        }
        #expect(ack.properties.contains(.assignedClientIdentifier("auto-1")))
        #expect(state.sessions["auto-1"] != nil)
    }

    @Test func emptyIdentifierWithPersistentSessionIsRefusedIn311() {
        let (commands, _) = run([open(alice), from(alice, connect("", version: .v3_1_1, cleanStart: false), .v3_1_1)])
        let refused = ConnAck(sessionPresent: false, reasonCode: .clientIdentifierNotValid, properties: [])
        #expect(sent(commands, to: alice) == [.connAck(refused)])
    }

    @Test func firstPacketMustBeConnect() {
        #expect(closes(run([open(alice), from(alice, .pingReq)]).0) == [alice])
    }

    @Test func connectTimeout() {
        #expect(closes(run([open(alice), tick(9)]).0).isEmpty)
        #expect(closes(run([open(alice), tick(10)]).0) == [alice])
    }

    @Test func sessionTakeover() {
        let (commands, state) = run(join(alice, "a") + join(bob, "a"))
        #expect(sent(commands, to: alice).last == .disconnect(Disconnect(reasonCode: .sessionTakenOver, properties: [])))
        #expect(closes(commands) == [alice])
        #expect(state.sessions["a"]?.connection == bob)
    }

    @Test func keepAliveTimeoutAfterOneAndAHalfIntervals() {
        let inputs = join(alice, "a", connect("a", keepAlive: 10))
        #expect(closes(run(inputs + [tick(15)]).0).isEmpty)
        let (commands, _) = run(inputs + [tick(16)])
        #expect(sent(commands, to: alice).last == .disconnect(Disconnect(reasonCode: .keepAliveTimeout, properties: [])))
        #expect(closes(commands) == [alice])
    }

    @Test func pingIsAnswered() {
        #expect(sent(run(join(alice, "a") + [from(alice, .pingReq)]).0, to: alice).last == .pingResp)
    }

    @Test func enhancedAuthenticationIsNotSupported() {
        let packet = connect("a", properties: [.authenticationMethod("SCRAM-SHA-1")])
        #expect(sent(run(join(alice, "a", packet)).0, to: alice).first.map {
            if case let .connAck(ack) = $0 { ack.reasonCode == .badAuthenticationMethod } else { false }
        } == true)
    }
}

@Suite struct BrokerSessionTests {
    private let persistent = connect("p", cleanStart: false, properties: [.sessionExpiryInterval(100)])

    @Test func resumedSessionReceivesWhatWasQueuedWhileOffline() {
        let (commands, state) = run(
            join(alice, "p", persistent) + [from(alice, subscribe([subscription("t")])), .connection(.closed(alice))]
                + join(bob, "pub") + [from(bob, publish("t", "while away", qos: .atLeastOnce))]
                + join(carol, "p", persistent)
        )
        #expect(sent(commands, to: carol).first.map { if case let .connAck(ack) = $0 { ack.sessionPresent } else { false } } == true)
        #expect(payloads(publishes(commands, to: carol)) == ["while away"])
        #expect(state.sessions["p"]?.inFlight.count == 1)
    }

    @Test func cleanStartDiscardsTheSession() {
        let (commands, state) = run(
            join(alice, "p", persistent) + [from(alice, subscribe([subscription("t")])), .connection(.closed(alice))]
                + join(bob, "p")
        )
        #expect(sent(commands, to: bob).first.map { if case let .connAck(ack) = $0 { !ack.sessionPresent } else { false } } == true)
        #expect(state.sessions["p"]?.subscriptions.isEmpty == true)
    }

    @Test func sessionExpires() {
        let (commands, state) = run(join(alice, "p", persistent) + [tick(1), .connection(.closed(alice)), tick(101)])
        #expect(commands.contains(.emit(.sessionExpired(clientIdentifier: "p"))))
        #expect(state.sessions["p"] == nil)
    }

    @Test func zeroExpiryEndsTheSessionOnDisconnect() {
        let (_, state) = run(join(alice, "a") + [.connection(.closed(alice))])
        #expect(state.sessions["a"] == nil)
    }

    @Test func unacknowledgedDeliveriesAreResentAsDuplicates() {
        let (commands, _) = run(
            join(alice, "p", persistent) + [from(alice, subscribe([subscription("t")]))]
                + join(bob, "pub") + [from(bob, publish("t", "once", qos: .atLeastOnce))]
                + [.connection(.closed(alice))] + join(carol, "p", persistent)
        )
        #expect(publishes(commands, to: carol).map(\.duplicate) == [true])
    }
}
