// SPDX-License-Identifier: Apache-2.0

import FP
import MQTT
import MQTTBroker
import Testing

/// A toy challenge/response method: the broker sends "nonce", the client must answer "proof".
private let challengeResponse = BrokerPolicy(
    authenticate: const(.success),
    mayPublish: { _, _ in true },
    maySubscribe: { _, _ in true },
    challenge: { _, method, data, round in
        switch (method, round, data) {
        case ("TOY", 0, _): .continue(data: Array("nonce".utf8))
        case ("TOY", 1, Array("proof".utf8)?): .accept(data: Array("welcome".utf8))
        case ("TOY", _, _): .refuse(.notAuthorized)
        default: .refuse(.badAuthenticationMethod)
        }
    }
)

private let toyConnect = connect("a", properties: [.authenticationMethod("TOY")])

private func answer(_ data: String, _ reason: ReasonCode = .continueAuthentication) -> Packet {
    .auth(Auth(reasonCode: reason, properties: [.authenticationMethod("TOY"), .authenticationData(Array(data.utf8))]))
}

@Suite struct BrokerAuthenticationTests {
    @Test func challengeThenAcceptance() {
        let (commands, state) = run(join(alice, "a", toyConnect) + [from(alice, answer("proof"))], policy: challengeResponse)
        let packets = sent(commands, to: alice)
        #expect(packets.first == .auth(Auth(
            reasonCode: .continueAuthentication,
            properties: [.authenticationMethod("TOY"), .authenticationData(Array("nonce".utf8))]
        )))
        guard case let .connAck(ack)? = packets.last else {
            Issue.record("expected CONNACK, got \(packets)")
            return
        }
        #expect(ack.reasonCode == .success)
        #expect(ack.properties.suffix(2) == [.authenticationMethod("TOY"), .authenticationData(Array("welcome".utf8))])
        #expect(state.sessions["a"] != nil)
    }

    @Test func wrongProofIsRefused() {
        let (commands, state) = run(join(alice, "a", toyConnect) + [from(alice, answer("guess"))], policy: challengeResponse)
        let refused = ConnAck(sessionPresent: false, reasonCode: .notAuthorized, properties: [])
        #expect(sent(commands, to: alice).last == .connAck(refused))
        #expect(closes(commands) == [alice])
        #expect(state.sessions.isEmpty)
    }

    @Test func unknownMethodIsRefused() {
        let unknown = connect("a", properties: [.authenticationMethod("OTHER")])
        let (commands, _) = run(join(alice, "a", unknown), policy: challengeResponse)
        let refused = ConnAck(sessionPresent: false, reasonCode: .badAuthenticationMethod, properties: [])
        #expect(sent(commands, to: alice).last == .connAck(refused))
    }

    @Test func otherPacketsDuringTheExchangeCloseTheConnection() {
        #expect(closes(run(join(alice, "a", toyConnect) + [from(alice, .pingReq)], policy: challengeResponse).0) == [alice])
    }

    @Test func reauthentication() {
        let (commands, _) = run(
            join(alice, "a", toyConnect)
                + [from(alice, answer("proof")), from(alice, answer("", .reAuthenticate)), from(alice, answer("proof"))],
            policy: challengeResponse
        )
        let toy = Property.authenticationMethod("TOY")
        #expect(sent(commands, to: alice).suffix(2) == [
            .auth(Auth(reasonCode: .continueAuthentication, properties: [toy, .authenticationData(Array("nonce".utf8))])),
            .auth(Auth(reasonCode: .success, properties: [toy, .authenticationData(Array("welcome".utf8))])),
        ])
    }
}
