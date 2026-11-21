// SPDX-License-Identifier: Apache-2.0

import FP
import MQTT
import MQTTClient
import Testing

private func refusal(_ reason: ReasonCode, to server: String) -> ConnAck {
    ConnAck(sessionPresent: false, reasonCode: reason, properties: [.serverReference(server)])
}

private let redirecting = options(reconnect: backoff)

@Suite struct ClientRedirectTests {
    @Test func serverMovedIsFollowedNowAndLater() {
        let moved = refusal(.serverMoved, to: "b:1883")
        let (commands, state) = run([.start, .connection(.opened(c1)), rx(.connAck(moved))], from: .initial(redirecting))
        #expect(commands.suffix(3) == [.close(c1), .emit(.redirected(to: "b:1883", permanent: true)), .redirect(c2, to: "b:1883")])
        let (later, _) = run(
            [.connection(.opened(c2)), rx(.connAck(accepted), on: c2), .connection(.closed(c2)), tick(1)],
            from: state
        )
        #expect(later.last == .redirect(.outgoing(3), to: "b:1883"))
    }

    @Test func useAnotherServerIsFollowedOnce() {
        let elsewhere = refusal(.useAnotherServer, to: "b:1883")
        let (commands, state) = run([.start, .connection(.opened(c1)), rx(.connAck(elsewhere))], from: .initial(redirecting))
        #expect(commands.last == .redirect(c2, to: "b:1883"))
        let (later, _) = run(
            [.connection(.opened(c2)), rx(.connAck(accepted), on: c2), .connection(.closed(c2)), tick(1)],
            from: state
        )
        #expect(later.last == .open(.outgoing(3)))
    }

    @Test func redirectWithoutAServerReferenceIsARefusal() {
        let bare = ConnAck(sessionPresent: false, reasonCode: .serverMoved, properties: [])
        let (commands, _) = run([.start, .connection(.opened(c1)), rx(.connAck(bare))], from: .initial(redirecting))
        #expect(commands.last == .fail(.connectionRefused(bare)))
    }

    @Test func redirectLoopsStop() {
        let moved = refusal(.serverMoved, to: "loop")
        let inputs = (1...6).flatMap { number -> [ClientInput] in
            let id = ConnectionID.outgoing(UInt64(number))
            return number == 1
                ? [.start, .connection(.opened(id)), rx(.connAck(moved), on: id)]
                : [.connection(.opened(id)), rx(.connAck(moved), on: id)]
        }
        let (commands, state) = run(inputs, from: .initial(redirecting))
        #expect(commands.last == .fail(.connectionRefused(moved)))
        #expect(state.phase == .closed)
    }

    @Test func serverDisconnectCanRedirect() {
        let notice = Disconnect(reasonCode: .useAnotherServer, properties: [.serverReference("b")])
        let (commands, _) = run([rx(.disconnect(notice))], from: connected(redirecting))
        #expect(commands == [
            .emit(.disconnected(notice, byServer: true)),
            .close(c1),
            .emit(.redirected(to: "b", permanent: false)),
            .redirect(c2, to: "b"),
        ])
    }
}
