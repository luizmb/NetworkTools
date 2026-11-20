// SPDX-License-Identifier: Apache-2.0

import FP
import MQTT

/// The MQTT broker as a pure state machine.
///
/// ``step(_:)`` takes the injected ``BrokerPolicy`` and returns the transition function: it folds
/// one ``BrokerInput`` into the ``BrokerState`` and returns the commands it causes. Time arrives as
/// clock ticks, so keep-alive (1.5 × the client's interval), the CONNECT timeout, Will Delay and
/// Session Expiry are pure comparisons.
///
/// It implements the server side of MQTT 3.1.1 and 5.0: authentication through the policy,
/// session takeover, clean and persistent sessions with expiry, wills (with delay), QoS 0/1/2 in
/// both directions with session resumption, retained messages with Retain Handling and Retain As
/// Published, No Local, Subscription Identifiers, shared subscriptions (round robin), overlapping
/// subscriptions (delivered once at the highest granted QoS), topic aliases from clients, the
/// broker's and each client's Receive Maximum and Maximum Packet Size, Maximum QoS, Message
/// Expiry, and per-topic authorization.
public enum BrokerMachine {
    /// The broker transition function for a policy.
    /// - Parameter policy: Authentication and authorization decisions.
    /// - Returns: The transition from one input to the commands it causes.
    public static func step(_ policy: BrokerPolicy) -> @Sendable (BrokerInput) -> Stateful<BrokerState, [BrokerCommand]> {
        { input in
            Stateful { state in transition(input, policy, &state) }
        }
    }

    private static func transition(_ input: BrokerInput, _ policy: BrokerPolicy, _ state: inout BrokerState) -> [BrokerCommand] {
        switch input {
        case let .publish(publish):
            return distribute(publish, from: nil, &state)
        case let .connection(.accepted(id)):
            state.links[id] = state.freshLink()
            return []
        case let .connection(.received(id, bytes)):
            return receive(bytes, on: id, policy, &state)
        case let .connection(.closed(id)),
             let .connection(.failed(id, _)):
            return dropped(id, &state)
        case let .connection(.tick(now)):
            state.now = now
            return timers(&state)
        case let .connection(.listenerFailed(error)):
            return [.fail(.listener(error))]
        case .connection(.opened),
             .connection(.openFailed):
            return []
        }
    }

    // MARK: - Bytes and packets

    private static func receive(
        _ bytes: [UInt8],
        on id: ConnectionID,
        _ policy: BrokerPolicy,
        _ state: inout BrokerState
    ) -> [BrokerCommand] {
        guard var link = state.links[id] else { return [] }
        let (decoded, stream) = PacketStream.feed(bytes).runStateful(link.stream)
        link.stream = stream
        link.lastReceived = state.now
        state.links[id] = link
        switch decoded {
        case let .success(packets):
            return packets.reduce(into: [BrokerCommand]()) { commands, packet in
                commands += state.links[id] == nil ? [] : handle(packet, on: id, policy, &state)
            }
        case let .failure(error):
            let reason: ReasonCode = if case .packetTooLarge = error { .packetTooLarge } else { .malformedPacket }
            return disconnect(id, reason, &state)
        }
    }

    private static func handle(
        _ packet: Packet,
        on id: ConnectionID,
        _ policy: BrokerPolicy,
        _ state: inout BrokerState
    ) -> [BrokerCommand] {
        switch (state.links[id]?.phase, packet) {
        case let (.awaitingConnect?, .connect(connect)):
            self.connect(connect, on: id, policy, &state)
        case (.awaitingConnect?, _):
            close(id, &state)
        case let (.connected(client)?, .publish(publish)):
            inbound(publish, from: client, on: id, policy, &state)
        case let (.connected(client)?, .pubRel(ack)):
            release(ack, client: client, on: id, &state)
        case let (.connected(client)?, .pubAck(ack)),
             let (.connected(client)?, .pubComp(ack)):
            completed(ack, client: client, &state)
        case let (.connected(client)?, .pubRec(ack)):
            received(ack, client: client, &state)
        case let (.connected(client)?, .subscribe(subscribe)):
            self.subscribe(subscribe, client: client, on: id, policy, &state)
        case let (.connected(client)?, .unsubscribe(unsubscribe)):
            self.unsubscribe(unsubscribe, client: client, &state)
        case (.connected?, .pingReq):
            send(.pingResp, on: id, state)
        case let (.connected(client)?, .disconnect(disconnect)):
            goodbye(disconnect, client: client, on: id, &state)
        case (.connected?, .auth):
            disconnect(id, .badAuthenticationMethod, &state)
        default:
            disconnect(id, .protocolError, &state)
        }
    }

    // MARK: - Connection ends

    /// The client said goodbye: its will is discarded unless it asked for it.
    private static func goodbye(
        _ disconnect: Disconnect,
        client: String,
        on id: ConnectionID,
        _ state: inout BrokerState
    ) -> [BrokerCommand] {
        let expiry = disconnect.properties.lazy.compactMap { property -> UInt32? in
            guard case let .sessionExpiryInterval(value) = property else { return nil }
            return value
        }.first
        if let expiry { state.sessions[client]?.expiry = expiry }
        if disconnect.reasonCode != .disconnectWithWillMessage { state.sessions[client]?.will = nil }
        return [.emit(.clientDisconnected(clientIdentifier: client, graceful: true))] + detach(id, &state) + [.close(id)]
    }

    /// The connection ended without DISCONNECT.
    private static func dropped(_ id: ConnectionID, _ state: inout BrokerState) -> [BrokerCommand] {
        guard let client = state.client(on: id) else {
            state.links[id] = nil
            return []
        }
        return [.emit(.clientDisconnected(clientIdentifier: client, graceful: false))] + detach(id, &state)
    }

    /// Ends a connection because of an error, telling MQTT 5 clients why.
    static func disconnect(_ id: ConnectionID, _ reason: ReasonCode, _ state: inout BrokerState) -> [BrokerCommand] {
        let notice = state.client(on: id) != nil && state.links[id]?.version == .v5
            ? send(.disconnect(Disconnect(reasonCode: reason, properties: [])), on: id, state)
            : []
        return notice + [.emit(.clientDropped(id, reason))] + detach(id, &state) + [.close(id)]
    }

    static func close(_ id: ConnectionID, _ state: inout BrokerState) -> [BrokerCommand] {
        state.links[id] = nil
        return [.close(id)]
    }

    /// Unbinds a connection from its session: schedules the will and starts the expiry clock.
    static func detach(_ id: ConnectionID, _ state: inout BrokerState) -> [BrokerCommand] {
        guard let client = state.client(on: id) else {
            state.links[id] = nil
            return []
        }
        state.links[id] = nil
        guard var session = state.sessions[client], session.connection == id else { return [] }
        session.connection = nil
        session.disconnectedAt = state.now
        if let will = session.will {
            let delay = min(willDelay(will), session.expiry)
            state.wills.append(BrokerState.ScheduledWill(will: will, clientIdentifier: client, at: state.now + .seconds(Int(delay))))
            session.will = nil
        }
        state.sessions[client] = session
        return session.expiry == 0 ? expire(client, &state) : []
    }

    private static func willDelay(_ will: Will) -> UInt32 {
        will.properties.lazy.compactMap { property -> UInt32? in
            guard case let .willDelayInterval(value) = property else { return nil }
            return value
        }.first ?? 0
    }

    static func expire(_ client: String, _ state: inout BrokerState) -> [BrokerCommand] {
        state.sessions[client] = nil
        return [.emit(.sessionExpired(clientIdentifier: client))]
    }

    // MARK: - Time

    private static func timers(_ state: inout BrokerState) -> [BrokerCommand] {
        let now = state.now
        let stale = state.links.compactMap { id, link -> (ConnectionID, ReasonCode?)? in
            switch link.phase {
            case let .awaitingConnect(since) where now - since >= state.options.connectTimeout:
                (id, nil)
            case .connected where link.keepAlive > 0 && now - link.lastReceived > .milliseconds(Int(link.keepAlive) * 1_500):
                (id, .keepAliveTimeout)
            default:
                nil
            }
        }
        let timeouts = stale.sorted { $0.0 < $1.0 }.flatMap { id, reason in
            reason.map { disconnect(id, $0, &state) } ?? close(id, &state)
        }
        let due = state.wills.filter { $0.at <= now }
        state.wills.removeAll { $0.at <= now }
        let wills = due.flatMap { scheduled in distribute(publish(scheduled.will), from: scheduled.clientIdentifier, &state) }
        let expired = state.sessions
            .filter { _, session in
                session.connection == nil && session.expiry != .max
                    && session.disconnectedAt.map { now - $0 >= .seconds(Int(session.expiry)) } == true
            }
            .keys.sorted()
            .flatMap { expire($0, &state) }
        return timeouts + wills + expired
    }

    private static func publish(_ will: Will) -> Publish {
        Publish(
            topic: will.topic,
            payload: will.payload,
            delivery: .make(will.qos, identifier: .first),
            retain: will.retain,
            duplicate: false,
            properties: will.properties.filter { if case .willDelayInterval = $0 { false } else { true } }
        )
    }

    // MARK: - Sending

    static func send(_ packet: Packet, on id: ConnectionID, _ state: BrokerState) -> [BrokerCommand] {
        state.links[id].map { [.send(id, packet, $0.version)] } ?? []
    }
}
