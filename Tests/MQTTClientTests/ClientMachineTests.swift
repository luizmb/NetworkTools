// SPDX-License-Identifier: Apache-2.0

import FP
import MQTT
import MQTTClient
import Testing

@Suite struct ClientHandshakeTests {
    @Test func startOpensAConnection() {
        let (commands, state) = run([.start], from: .initial(options()))
        #expect(commands == [.open(c1)])
        #expect(state.phase == .connecting(c1, since: .zero))
    }

    @Test func openedConnectionSendsConnectAnnouncingTheMaximumPacketSize() {
        let (commands, _) = run([.start, .connection(.opened(c1))], from: .initial(options()))
        #expect(commands.last == .send(c1, expectedConnect(options()), .v5))
    }

    @Test func connectIn311HasNoProperties() {
        let (commands, _) = run([.start, .connection(.opened(c1))], from: .initial(options(.v3_1_1)))
        #expect(commands.last == .send(c1, expectedConnect(options(.v3_1_1)), .v3_1_1))
    }

    @Test func connAckConnects() {
        let (commands, state) = run([.start, .connection(.opened(c1)), rx(.connAck(accepted))], from: .initial(options()))
        #expect(commands.last == .emit(.connected(accepted)))
        #expect(state.phase == .connected(c1))
    }

    @Test func refusedConnectionFailsWithoutRetry() {
        let refused = ConnAck(sessionPresent: false, reasonCode: .notAuthorized, properties: [])
        let (commands, state) = run(
            [.start, .connection(.opened(c1)), rx(.connAck(refused))],
            from: .initial(options(reconnect: backoff))
        )
        #expect(commands.suffix(2) == [.close(c1), .fail(.connectionRefused(refused))])
        #expect(state.phase == .closed)
    }

    @Test func busyServerIsRetried() {
        let busy = ConnAck(sessionPresent: false, reasonCode: .serverBusy, properties: [])
        let (commands, state) = run(
            [.start, .connection(.opened(c1)), rx(.connAck(busy))],
            from: .initial(options(reconnect: backoff))
        )
        #expect(commands.suffix(2) == [.close(c1), .emit(.connectionLost(.connectionRefused(busy), retryingIn: .seconds(1)))])
        #expect(state.phase == .reconnecting(at: .seconds(1)))
    }

    @Test func requestsBeforeConnAckAreQueuedThenSent() {
        let (commands, _) = run(
            [.start, request(.publish(message(.atMostOnce))), .connection(.opened(c1)), rx(.connAck(accepted))],
            from: .initial(options())
        )
        #expect(events(commands) == [.connected(accepted)])
        #expect(publishes(commands).map(\.topic) == [topic("a/b")])
    }

    @Test func packetBeforeConnAckIsAViolation() {
        let (commands, state) = run([.start, .connection(.opened(c1)), rx(.pingResp)], from: .initial(options()))
        #expect(commands.suffix(3) == [
            .send(c1, .disconnect(Disconnect(reasonCode: .protocolError, properties: [])), .v5),
            .close(c1),
            .fail(.protocolViolation(.unexpectedPacket(.pingResp))),
        ])
        #expect(state.phase == .closed)
    }

    @Test func connAckSplitAcrossChunks() {
        let bytes = wire(.connAck(accepted))
        let (commands, state) = run(
            [.start, .connection(.opened(c1))] + bytes.map { .connection(.received(c1, [$0])) },
            from: .initial(options())
        )
        #expect(commands.last == .emit(.connected(accepted)))
        #expect(state.phase == .connected(c1))
    }

    @Test func malformedBytesAbort() {
        let (commands, _) = run([.start, .connection(.opened(c1)), .connection(.received(c1, [0x00, 0x00]))], from: .initial(options()))
        #expect(commands.last == .fail(.decoding(.decoding(.reservedPacketType(0)))))
    }

    @Test func connectTimeout() {
        let (commands, _) = run([.start, tick(5), .connection(.opened(c1)), tick(16)], from: .initial(options()))
        #expect(commands.suffix(2) == [.close(c1), .fail(.connectTimeout)])
    }

    @Test func assignedClientIdentifierIsUsedOnReconnect() {
        let ack = ConnAck(sessionPresent: false, reasonCode: .success, properties: [.assignedClientIdentifier("auto-1")])
        let start = connected(options(reconnect: backoff), ack: ack)
        let lost = run([.connection(.closed(c1)), tick(1), .connection(.opened(c2))], from: start)
        guard case let .connect(connect)? = sent(lost.0).last else {
            Issue.record("expected a CONNECT")
            return
        }
        #expect(connect.clientIdentifier == "auto-1")
    }
}

@Suite struct ClientKeepAliveTests {
    @Test func pingsOnlyWhenIdleForAKeepAliveInterval() {
        #expect(run([tick(29)], from: connected()).0.isEmpty)
        #expect(run([tick(30)], from: connected()).0 == [.send(c1, .pingReq, .v5)])
    }

    @Test func trafficPostponesThePing() {
        let (commands, _) = run([tick(20), request(.publish(message(.atMostOnce))), tick(30), tick(50)], from: connected())
        #expect(sent(commands).filter { $0 == .pingReq }.count == 1)
        #expect(sent(commands).last == .pingReq)
    }

    @Test func pongClearsThePing() {
        let (commands, state) = run([tick(30), rx(.pingResp), tick(60)], from: connected())
        #expect(sent(commands) == [.pingReq, .pingReq])
        #expect(state.phase == .connected(c1))
    }

    @Test func missingPongLosesTheConnection() {
        let (commands, state) = run([tick(30), tick(60)], from: connected())
        #expect(commands.suffix(2) == [.close(c1), .fail(.keepAliveTimeout)])
        #expect(state.phase == .closed)
    }

    @Test func serverKeepAliveOverridesTheClients() {
        let ack = ConnAck(sessionPresent: false, reasonCode: .success, properties: [.serverKeepAlive(5)])
        #expect(run([tick(5)], from: connected(ack: ack)).0 == [.send(c1, .pingReq, .v5)])
    }

    @Test func zeroDisablesKeepAlive() {
        #expect(run([tick(1_000)], from: connected(options(keepAlive: 0))).0.isEmpty)
    }
}

@Suite struct ClientDisconnectTests {
    @Test func requestedDisconnect() {
        let (commands, state) = run([request(.disconnect(.normal))], from: connected())
        #expect(commands == [
            .send(c1, .disconnect(.normal), .v5),
            .emit(.disconnected(.normal, byServer: false)),
            .close(c1),
            .finish,
        ])
        #expect(state.phase == .closed)
    }

    @Test func serverDisconnectFinishesWithoutAPolicy() {
        let notice = Disconnect(reasonCode: .serverShuttingDown, properties: [])
        let (commands, _) = run([rx(.disconnect(notice))], from: connected())
        #expect(commands == [.emit(.disconnected(notice, byServer: true)), .close(c1), .finish])
    }

    @Test func serverShutdownIsRetriedWithAPolicy() {
        let notice = Disconnect(reasonCode: .serverShuttingDown, properties: [])
        let (commands, state) = run([rx(.disconnect(notice))], from: connected(options(reconnect: backoff)))
        #expect(commands == [
            .emit(.disconnected(notice, byServer: true)),
            .close(c1),
            .emit(.connectionLost(.disconnectedByServer(notice), retryingIn: .seconds(1))),
        ])
        #expect(state.phase == .reconnecting(at: .seconds(1)))
    }

    @Test func sessionTakenOverIsNotRetried() {
        let notice = Disconnect(reasonCode: .sessionTakenOver, properties: [])
        let (commands, _) = run([rx(.disconnect(notice))], from: connected(options(reconnect: backoff)))
        #expect(commands.last == .finish)
    }

    @Test func transportClosedFailsWithoutAPolicy() {
        #expect(run([.connection(.closed(c1))], from: connected()).0 == [.close(c1), .fail(.connectionClosed)])
    }

    @Test func staleConnectionInputIsIgnored() {
        #expect(run([.connection(.closed(c2)), .connection(.received(c2, [0xD0, 0x00]))], from: connected()).0.isEmpty)
    }

    @Test func nothingHappensOnceClosed() {
        let (_, closed) = run([request(.disconnect(.normal))], from: connected())
        #expect(run([tick(1_000), .connection(.closed(c1)), rx(.pingResp)], from: closed).0.isEmpty)
    }
}
