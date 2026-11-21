// SPDX-License-Identifier: Apache-2.0

import FP
import MQTT

// Authentication Data may be absent or present-and-empty: these are different on the wire, so `[UInt8]?` is intended.
// swiftlint:disable discouraged_optional_collection

// MARK: - CONNECT

extension BrokerMachine {
    static func connect(_ connect: Connect, on id: ConnectionID, _ policy: BrokerPolicy, _ state: inout BrokerState) -> [BrokerCommand] {
        let version = connect.protocolVersion
        state.links[id]?.version = version
        state.links[id]?.stream.version = version
        let anonymous = connect.clientIdentifier.isEmpty
        let refusal: ReasonCode? = anonymous && version == .v3_1_1 && !connect.cleanStart ? .clientIdentifierNotValid
            : connect.will.map { $0.qos > state.options.maximumQoS } == true ? .qosNotSupported
            : connect.will.map { $0.retain && !state.options.retainAvailable } == true ? .retainNotSupported
            : Optional(policy.authenticate(connect)).flatMap { $0.isFailure ? $0 : nil }
        if let refusal {
            return refuse(id, refusal, version: version, &state)
        }
        guard let method = authenticationMethod(connect.properties) else {
            return admit(connect, on: id, authentication: [], &state)
        }
        return authenticationStep(
            policy.challenge(connect.clientIdentifier, method, authenticationData(connect.properties), 0),
            connect: connect,
            method: method,
            round: 0,
            on: id,
            &state
        )
    }

    /// The client answered a challenge during CONNECT.
    static func continueAuthentication( // swiftlint:disable:this function_parameter_count
        _ auth: Auth,
        connect: Connect,
        method: String,
        round: Int,
        on id: ConnectionID,
        _ policy: BrokerPolicy,
        _ state: inout BrokerState
    ) -> [BrokerCommand] {
        guard auth.reasonCode == .continueAuthentication, authenticationMethod(auth.properties) == method else {
            return refuse(id, .protocolError, version: .v5, &state)
        }
        return authenticationStep(
            policy.challenge(connect.clientIdentifier, method, authenticationData(auth.properties), round),
            connect: connect,
            method: method,
            round: round,
            on: id,
            &state
        )
    }

    private static func authenticationStep(
        _ step: AuthenticationStep,
        connect: Connect,
        method: String,
        round: Int,
        on id: ConnectionID,
        _ state: inout BrokerState
    ) -> [BrokerCommand] {
        let since = state.now
        switch step {
        case let .accept(data):
            state.links[id]?.authenticationMethod = method
            return admit(connect, on: id, authentication: authenticationProperties(method, data), &state)
        case let .continue(data):
            state.links[id]?.phase = .authenticating(connect, method: method, round: round + 1, since: since)
            let challenge = Auth(reasonCode: .continueAuthentication, properties: authenticationProperties(method, data))
            return send(.auth(challenge), on: id, state)
        case let .refuse(reason):
            return refuse(id, reason, version: .v5, &state)
        }
    }

    /// Re-authentication of a connected client (AUTH with Re-authenticate, then Continue steps).
    static func reauthenticate(
        _ auth: Auth,
        client: String,
        on id: ConnectionID,
        _ policy: BrokerPolicy,
        _ state: inout BrokerState
    ) -> [BrokerCommand] {
        let round = state.links[id]?.reauthenticationRound
        let expected: ReasonCode = round == nil ? .reAuthenticate : .continueAuthentication
        guard let method = state.links[id]?.authenticationMethod,
              auth.reasonCode == expected,
              authenticationMethod(auth.properties) == method else {
            return disconnect(id, .protocolError, &state)
        }
        switch policy.challenge(client, method, authenticationData(auth.properties), round ?? 0) {
        case let .accept(data):
            state.links[id]?.reauthenticationRound = nil
            return send(.auth(Auth(reasonCode: .success, properties: authenticationProperties(method, data))), on: id, state)
        case let .continue(data):
            state.links[id]?.reauthenticationRound = (round ?? 0) + 1
            let challenge = Auth(reasonCode: .continueAuthentication, properties: authenticationProperties(method, data))
            return send(.auth(challenge), on: id, state)
        case let .refuse(reason):
            return disconnect(id, reason, &state)
        }
    }

    private static func authenticationMethod(_ properties: [Property]) -> String? {
        properties.lazy.compactMap { property -> String? in
            guard case let .authenticationMethod(method) = property else { return nil }
            return method
        }.first
    }

    private static func authenticationData(_ properties: [Property]) -> [UInt8]? {
        properties.lazy.compactMap { property -> [UInt8]? in
            guard case let .authenticationData(data) = property else { return nil }
            return data
        }.first
    }

    private static func authenticationProperties(_ method: String, _ data: [UInt8]?) -> [Property] {
        [.authenticationMethod(method)] + (data.map { [.authenticationData($0)] } ?? [])
    }

    /// Accepts an authenticated CONNECT: session takeover, session creation or resumption, CONNACK.
    private static func admit(
        _ connect: Connect,
        on id: ConnectionID,
        authentication: [Property],
        _ state: inout BrokerState
    ) -> [BrokerCommand] {
        let version = connect.protocolVersion
        let anonymous = connect.clientIdentifier.isEmpty
        let client = anonymous ? assignIdentifier(&state) : connect.clientIdentifier
        let takeover = takeOver(client, by: id, &state)
        let existing = connect.cleanStart ? nil : state.sessions[client]
        state.wills.removeAll { $0.clientIdentifier == client }
        var session = existing ?? BrokerState.newSession(
            version: version,
            expiry: expiry(connect),
            will: connect.will,
            connection: id
        )
        session.connection = id
        session.version = version
        session.expiry = expiry(connect)
        session.will = connect.will
        session.disconnectedAt = nil
        state.sessions[client] = session
        configure(id, connect, client: client, &state)
        let properties = version == .v5 ? connAckProperties(connect, assigned: anonymous ? client : nil, state) + authentication : []
        let ack = ConnAck(sessionPresent: existing != nil, reasonCode: .success, properties: properties)
        return takeover
            + send(.connAck(ack), on: id, state)
            + [.emit(.clientConnected(clientIdentifier: client, id, resumed: existing != nil))]
            + (existing != nil ? resume(client, &state) : [])
    }

    private static func refuse(
        _ id: ConnectionID,
        _ reason: ReasonCode,
        version: ProtocolVersion,
        _ state: inout BrokerState
    ) -> [BrokerCommand] {
        let code = version == .v3_1_1 && reason.connectReturnCode == nil ? ReasonCode.notAuthorized : reason
        let ack = ConnAck(sessionPresent: false, reasonCode: code, properties: [])
        let commands = send(.connAck(ack), on: id, state) + [.emit(.clientRefused(id, code))]
        return commands + close(id, &state)
    }

    private static func assignIdentifier(_ state: inout BrokerState) -> String {
        let prefix = state.options.assignedIdentifierPrefix
        let sessions = state.sessions
        let number = Swift.sequence(first: state.nextAssigned) { $0 + 1 }
            .first { sessions[prefix + String($0)] == nil } ?? state.nextAssigned
        state.nextAssigned = number + 1
        return prefix + String(number)
    }

    /// A second connection with the same client identifier replaces the first one.
    private static func takeOver(_ client: String, by id: ConnectionID, _ state: inout BrokerState) -> [BrokerCommand] {
        guard let previous = state.sessions[client]?.connection, previous != id else { return [] }
        let notice = state.links[previous]?.version == .v5
            ? send(.disconnect(Disconnect(reasonCode: .sessionTakenOver, properties: [])), on: previous, state)
            : []
        state.links[previous] = nil
        state.sessions[client]?.connection = nil
        return notice + [.emit(.clientDropped(previous, .sessionTakenOver)), .close(previous)]
    }

    /// Session Expiry Interval: the MQTT 5 property, or "never" / "on disconnect" for 3.1.1.
    private static func expiry(_ connect: Connect) -> UInt32 {
        switch connect.protocolVersion {
        case .v3_1_1:
            connect.cleanStart ? 0 : .max
        case .v5:
            connect.properties.lazy.compactMap { property -> UInt32? in
                guard case let .sessionExpiryInterval(value) = property else { return nil }
                return value
            }.first ?? 0
        }
    }

    private static func configure(_ id: ConnectionID, _ connect: Connect, client: String, _ state: inout BrokerState) {
        let properties = connect.properties
        state.links[id]?.phase = .connected(clientIdentifier: client)
        state.links[id]?.keepAlive = state.options.serverKeepAlive ?? connect.keepAlive
        state.links[id]?.clientReceiveMaximum = properties.lazy.compactMap { property -> Int? in
            guard case let .receiveMaximum(value) = property else { return nil }
            return Int(value)
        }.first ?? 65_535
        state.links[id]?.clientMaximumPacketSize = properties.lazy.compactMap { property -> Int? in
            guard case let .maximumPacketSize(value) = property else { return nil }
            return Int(value)
        }.first
    }

    private static func connAckProperties(_ connect: Connect, assigned: String?, _ state: BrokerState) -> [Property] {
        let options = state.options
        let entries: [Property?] = [
            assigned.map(Property.assignedClientIdentifier),
            options.receiveMaximum < .max ? .receiveMaximum(options.receiveMaximum) : nil,
            options.maximumQoS < .exactlyOnce ? .maximumQoS(options.maximumQoS.rawValue) : nil,
            options.retainAvailable ? nil : .retainAvailable(0),
            .maximumPacketSize(UInt32(clamping: options.maximumPacketSize)),
            options.topicAliasMaximum > 0 ? .topicAliasMaximum(options.topicAliasMaximum) : nil,
            options.wildcardSubscriptionAvailable ? nil : .wildcardSubscriptionAvailable(0),
            options.subscriptionIdentifierAvailable ? nil : .subscriptionIdentifierAvailable(0),
            options.sharedSubscriptionAvailable ? nil : .sharedSubscriptionAvailable(0),
            options.serverKeepAlive.map(Property.serverKeepAlive),
        ]
        return entries.compactMap(id)
    }

    /// A resumed session: resend unacknowledged messages (as duplicates) and PUBRELs in order,
    /// then whatever was queued while the client was away.
    private static func resume(_ client: String, _ state: inout BrokerState) -> [BrokerCommand] {
        guard let session = state.sessions[client], let id = session.connection else { return [] }
        let resent = session.inFlight.flatMap { delivery -> [BrokerCommand] in
            var publish = delivery.publish
            publish.duplicate = true
            return delivery.released
                ? send(.pubRel(.success(delivery.identifier)), on: id, state)
                : send(.publish(publish), on: id, state)
        }
        return resent + drain(client, &state)
    }
}

// swiftlint:enable discouraged_optional_collection
