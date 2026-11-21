// SPDX-License-Identifier: Apache-2.0

import FP
import MQTT

/// Something that happens to a client.
public enum ClientInput: Sendable, Hashable {
    /// Start: open the first connection.
    case start
    /// The application asked for something.
    case request(ClientRequest)
    /// Something happened to a connection, or the clock ticked.
    case connection(ConnectionInput)
}

/// What the client asks the runtime to do.
public typealias ClientCommand = RuntimeCommand<ClientEvent, ClientError>

/// The MQTT client protocol as a pure state machine.
///
/// ``step(_:)`` folds one ``ClientInput`` into the ``ClientState`` and returns the commands it
/// causes. It never touches a socket or a clock: time arrives as `.connection(.tick(now))`, and
/// every timer — keep-alive, connect timeout, reconnect backoff — is a comparison against it.
/// Everything is therefore tested by feeding inputs and comparing commands.
///
/// It covers the client side of MQTT 3.1.1 and 5.0: the handshake, keep-alive (pinging only when
/// idle, honouring Server Keep Alive), QoS 0/1/2 in both directions, session resumption (resending
/// unacknowledged PUBLISH and PUBREL in order), automatic re-subscription when the server lost the
/// session, reconnecting with backoff, the server's Receive Maximum, Maximum Packet Size,
/// Maximum QoS and feature flags, topic aliases in both directions, this client's own Receive
/// Maximum and Topic Alias Maximum, and protocol violations.
public enum ClientMachine {
    /// One transition of the client protocol.
    /// - Parameter input: What happened.
    /// - Returns: A state step producing the commands, in order.
    public static func step(_ input: ClientInput) -> Stateful<ClientState, [ClientCommand]> {
        Stateful { state in
            state.phase == .closed ? [] : transition(input, &state)
        }
    }

    private static func transition(_ input: ClientInput, _ state: inout ClientState) -> [ClientCommand] {
        switch input {
        case .start:
            state.phase == .idle ? open(&state) : []
        case let .request(request):
            perform(request, &state)
        case let .connection(event):
            connection(event, &state)
        }
    }

    // MARK: - Connections

    private static func connection(_ event: ConnectionInput, _ state: inout ClientState) -> [ClientCommand] {
        switch event {
        case let .tick(now):
            state.now = now
            return timers(&state)
        case let .opened(id) where state.isOpening(id):
            return handshake(id, &state)
        case let .openFailed(id, error) where state.connection == id:
            return lose(.transport(error), &state)
        case let .received(id, bytes) where state.connection == id:
            return receive(bytes, &state)
        case let .closed(id) where state.connection == id:
            return lose(.connectionClosed, &state)
        case let .failed(id, error) where state.connection == id:
            return lose(.transport(error), &state)
        case let .accepted(id):
            return [.close(id)]
        case .opened,
             .openFailed,
             .received,
             .closed,
             .failed,
             .listenerFailed:
            return []
        }
    }

    static func open(_ state: inout ClientState) -> [ClientCommand] {
        let id = ConnectionID.outgoing(state.nextConnection)
        state.nextConnection += 1
        state.phase = .connecting(id, since: state.now)
        state.link = ClientState.freshLink(state.options)
        guard let redirect = state.redirect else { return [.open(id)] }
        if !redirect.permanent { state.redirect = nil }
        return [.redirect(id, to: redirect.server)]
    }

    /// The redirect a CONNACK or DISCONNECT asks for: "Use another server" or "Server moved" with
    /// a Server Reference.
    static func redirection(_ reason: ReasonCode, _ properties: [Property]) -> ClientState.Redirect? {
        let reference = properties.lazy.compactMap { property -> String? in
            guard case let .serverReference(value) = property else { return nil }
            return value
        }.first
        return switch (reason, reference) {
        case let (.useAnotherServer, .some(server)): ClientState.Redirect(server: server, permanent: false)
        case let (.serverMoved, .some(server)): ClientState.Redirect(server: server, permanent: true)
        default: nil
        }
    }

    /// Follows a redirect now, unless too many happened in a row (then fails with `error`).
    static func follow(_ redirect: ClientState.Redirect, otherwise error: ClientError, _ state: inout ClientState) -> [ClientCommand] {
        let close = state.connection.map { [ClientCommand.close($0)] } ?? []
        guard state.redirectsFollowed < ClientState.maximumRedirects else {
            return end(&state, close + [.fail(error)])
        }
        state.redirectsFollowed += 1
        state.redirect = redirect
        return close + [.emit(.redirected(to: redirect.server, permanent: redirect.permanent))] + open(&state)
    }

    private static func handshake(_ id: ConnectionID, _ state: inout ClientState) -> [ClientCommand] {
        state.phase = .awaitingConnAck(id, since: state.now)
        let connect = Packet.connect(connectPacket(state))
        switch connect.encode(for: state.options.version) {
        case .success:
            return send(connect, &state)
        case let .failure(error):
            return end(&state, [.close(id), .fail(.encoding(error))])
        }
    }

    private static func connectPacket(_ state: ClientState) -> Connect {
        let options = state.options
        let announcesSize = options.properties.contains { if case .maximumPacketSize = $0 { true } else { false } }
        let properties = options.version == .v5 && !announcesSize
            ? options.properties + [.maximumPacketSize(UInt32(clamping: options.maximumPacketSize))]
            : options.properties
        return Connect(
            protocolVersion: options.version,
            clientIdentifier: state.clientIdentifier,
            cleanStart: options.cleanStart,
            keepAlive: options.keepAlive,
            will: options.will,
            userName: options.userName,
            password: options.password,
            properties: properties
        )
    }

    private static func timers(_ state: inout ClientState) -> [ClientCommand] {
        switch state.phase {
        case let .connecting(_, since),
             let .awaitingConnAck(_, since):
            state.now - since >= state.options.connectTimeout ? lose(.connectTimeout, &state) : []
        case .connected:
            keepAlive(&state)
        case let .reconnecting(at) where state.now >= at:
            open(&state)
        case .idle,
             .reconnecting,
             .closed:
            []
        }
    }

    private static func keepAlive(_ state: inout ClientState) -> [ClientCommand] {
        let interval = Duration.seconds(Int(state.keepAlive))
        guard state.keepAlive > 0 else { return [] }
        switch state.link.pingSentAt {
        case let .some(sentAt):
            return state.now - sentAt >= interval ? lose(.keepAliveTimeout, &state) : []
        case .none where state.now - state.link.lastSent >= interval:
            state.link.pingSentAt = state.now
            return send(.pingReq, &state)
        case .none:
            return []
        }
    }

    /// The connection is gone: reconnect when the error and the policy allow it, fail otherwise.
    static func lose(_ error: ClientError, _ state: inout ClientState) -> [ClientCommand] {
        let close = state.connection.map { [ClientCommand.close($0)] } ?? []
        guard isRetryable(error), let delay = state.options.reconnect.delay(beforeAttempt: state.failedAttempts + 1) else {
            return end(&state, close + [.fail(error)])
        }
        state.failedAttempts += 1
        state.phase = .reconnecting(at: state.now + delay)
        state.link = ClientState.freshLink(state.options)
        return close + [.emit(.connectionLost(error, retryingIn: delay))]
    }

    /// Ends the session because of the server, telling it why first when MQTT 5 allows it.
    static func abort(_ reason: ReasonCode, _ error: ClientError, _ state: inout ClientState) -> [ClientCommand] {
        let notice = state.options.version == .v5
            ? send(.disconnect(Disconnect(reasonCode: reason, properties: [])), &state)
            : []
        return end(&state, notice + (state.connection.map { [.close($0)] } ?? []) + [.fail(error)])
    }

    static func end(_ state: inout ClientState, _ commands: [ClientCommand]) -> [ClientCommand] {
        state.phase = .closed
        return commands
    }

    static func isRetryable(_ error: ClientError) -> Bool {
        switch error {
        case .transport,
             .connectionClosed,
             .connectTimeout,
             .keepAliveTimeout:
            true
        case let .connectionRefused(ack):
            [.serverUnavailable, .serverBusy, .connectionRateExceeded, .quotaExceeded, .unspecifiedError].contains(ack.reasonCode)
        case let .disconnectedByServer(disconnect):
            [
                .normalDisconnection, .unspecifiedError, .implementationSpecificError, .serverBusy, .serverShuttingDown,
                .keepAliveTimeout, .maximumConnectTime, .messageRateTooHigh, .quotaExceeded, .administrativeAction,
                .connectionRateExceeded,
            ].contains(disconnect.reasonCode)
        case .encoding,
             .decoding,
             .protocolViolation,
             .packetIdentifiersExhausted:
            false
        }
    }

    /// Sends a packet on the current connection, recording the time for keep-alive.
    static func send(_ packet: Packet, _ state: inout ClientState) -> [ClientCommand] {
        guard let id = state.connection else { return [] }
        state.link.lastSent = state.now
        return [.send(id, packet, state.options.version)]
    }
}

extension ClientState {
    func isOpening(_ id: ConnectionID) -> Bool {
        if case .connecting(id, _) = phase { true } else { false }
    }
}
