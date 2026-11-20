// SPDX-License-Identifier: Apache-2.0

import FP
import MQTT

// MARK: - Server packets

extension ClientMachine {
    static func receive(_ bytes: [UInt8], _ state: inout ClientState) -> [ClientCommand] {
        let (decoded, stream) = PacketStream.feed(bytes).runStateful(state.link.stream)
        state.link.stream = stream
        switch decoded {
        case let .success(packets):
            let id = state.connection
            return packets.reduce(into: [ClientCommand]()) { commands, packet in
                commands += state.connection == id && state.phase != .closed ? handle(packet, &state) : []
            }
        case let .failure(error):
            let reason: ReasonCode = if case .packetTooLarge = error { .packetTooLarge } else { .malformedPacket }
            return abort(reason, .decoding(error), &state)
        }
    }

    private static func handle(_ packet: Packet, _ state: inout ClientState) -> [ClientCommand] {
        switch (state.phase, packet) {
        case let (.awaitingConnAck, .connAck(ack)):
            return accepted(ack, &state)
        case let (.awaitingConnAck, .auth(auth)),
             let (.connected, .auth(auth)):
            return [.emit(.authenticationChallenge(auth))]
        case let (.awaitingConnAck, .disconnect(disconnect)),
             let (.connected, .disconnect(disconnect)):
            return disconnected(disconnect, &state)
        case let (.connected, .publish(publish)):
            return incoming(publish, &state)
        case let (.connected, .pubAck(ack)):
            return acknowledge(ack, .pubAck, &state)
        case let (.connected, .pubRec(ack)):
            return acknowledge(ack, .pubRec, &state)
        case let (.connected, .pubRel(ack)):
            return release(ack, &state)
        case let (.connected, .pubComp(ack)):
            return acknowledge(ack, .pubComp, &state)
        case let (.connected, .subAck(ack)):
            return acknowledge(ack, &state)
        case let (.connected, .unsubAck(ack)):
            return acknowledge(ack, &state)
        case (.connected, .pingResp):
            state.link.pingSentAt = nil
            return []
        default:
            return abort(.protocolError, .protocolViolation(.unexpectedPacket(packet.type)), &state)
        }
    }

    private static func disconnected(_ disconnect: Disconnect, _ state: inout ClientState) -> [ClientCommand] {
        let event = ClientCommand.emit(.disconnected(disconnect, byServer: true))
        let error = ClientError.disconnectedByServer(disconnect)
        if let redirect = redirection(disconnect.reasonCode, disconnect.properties) {
            return [event] + follow(redirect, otherwise: error, &state)
        }
        let retry = isRetryable(error) && state.options.reconnect.delay(beforeAttempt: state.failedAttempts + 1) != nil
        return [event] + (retry ? lose(error, &state) : end(&state, (state.connection.map { [.close($0)] } ?? []) + [.finish]))
    }

    // MARK: CONNACK

    private static func accepted(_ ack: ConnAck, _ state: inout ClientState) -> [ClientCommand] {
        guard !ack.reasonCode.isFailure else {
            return redirection(ack.reasonCode, ack.properties)
                .map { follow($0, otherwise: .connectionRefused(ack), &state) }
                ?? lose(.connectionRefused(ack), &state)
        }
        guard case let .awaitingConnAck(id, _) = state.phase else { return [] }
        let resumed = state.hasConnected || !state.options.cleanStart
        state.phase = .connected(id)
        state.failedAttempts = 0
        state.redirectsFollowed = 0
        state.link.server = state.options.version == .v5 ? ServerLimits.from(ack.properties) : .defaults
        state.link.pingSentAt = nil
        state.clientIdentifier = state.link.server.assignedClientIdentifier ?? state.clientIdentifier
        let session = ack.sessionPresent ? resumeSession(&state) : renewSession(resubscribe: resumed, &state)
        state.hasConnected = true
        return [.emit(.connected(ack))] + session + flush(&state)
    }

    /// The server kept the session: resend every unacknowledged PUBLISH (as a duplicate) and
    /// PUBREL, and every unanswered SUBSCRIBE/UNSUBSCRIBE, in their original order.
    private static func resumeSession(_ state: inout ClientState) -> [ClientCommand] {
        state.inFlight.reduce(into: [ClientCommand]()) { commands, entry in
            commands += resend(entry, duplicate: true, &state)
        }
    }

    /// The server has no session: forget received QoS 2 state, complete the QoS 2 messages it
    /// already acknowledged with PUBREC, resend everything else as new, and re-subscribe.
    private static func renewSession(resubscribe: Bool, _ state: inout ClientState) -> [ClientCommand] {
        state.receivedQoS2 = []
        let released = state.inFlight.compactMap { entry -> ClientCommand? in
            guard case let .awaitingPubComp(publish) = entry.stage else { return nil }
            return .emit(.published(publish, .success(entry.identifier)))
        }
        state.inFlight.removeAll { if case .awaitingPubComp = $0.stage { true } else { false } }
        let resent = state.inFlight.reduce(into: [ClientCommand]()) { commands, entry in
            commands += resend(entry, duplicate: false, &state)
        }
        let pending = Set(state.inFlight.flatMap { entry -> [TopicFilter] in
            guard case let .subscribing(subscriptions, _) = entry.stage else { return [] }
            return subscriptions.map(\.filter)
        })
        let renewed = state.subscriptions.filter { !pending.contains($0.filter) }
        let resubscription = resubscribe && !renewed.isEmpty
            ? subscribe(renewed, properties: [], &state)
            : []
        return released + resent + resubscription
    }

    private static func resend(_ entry: ClientState.Entry, duplicate: Bool, _ state: inout ClientState) -> [ClientCommand] {
        switch entry.stage {
        case var .awaitingPubAck(publish),
             var .awaitingPubRec(publish):
            publish.duplicate = duplicate
            return sendPublish(publish, &state)
        case .awaitingPubComp:
            return send(.pubRel(.success(entry.identifier)), &state)
        case let .subscribing(subscriptions, properties):
            let subscribe = Subscribe(packetIdentifier: entry.identifier, subscriptions: subscriptions, properties: properties)
            return send(.subscribe(subscribe), &state)
        case let .unsubscribing(filters, properties):
            let unsubscribe = Unsubscribe(packetIdentifier: entry.identifier, filters: filters, properties: properties)
            return send(.unsubscribe(unsubscribe), &state)
        }
    }

    // MARK: PUBLISH

    private static func incoming(_ publish: Publish, _ state: inout ClientState) -> [ClientCommand] {
        switch resolveAlias(publish, &state) {
        case let .failure(violation):
            let reason: ReasonCode = if case .missingTopic = violation { .protocolError } else { .topicAliasInvalid }
            return abort(reason, .protocolViolation(violation), &state)
        case let .success(resolved):
            return deliver(resolved, &state)
        }
    }

    private static func resolveAlias(_ publish: Publish, _ state: inout ClientState) -> Result<Publish, ProtocolViolation> {
        let alias = publish.properties.lazy.compactMap { property -> UInt16? in
            guard case let .topicAlias(value) = property else { return nil }
            return value
        }.first
        switch alias {
        case .none:
            return publish.topic.rawValue.isEmpty ? .failure(.missingTopic) : .success(publish)
        case let .some(value) where value == 0 || value > state.topicAliasMaximum:
            return .failure(.topicAliasInvalid(value))
        case let .some(value) where publish.topic.rawValue.isEmpty:
            guard let topic = state.link.inboundAliases[value] else { return .failure(.topicAliasInvalid(value)) }
            var resolved = publish
            resolved.topic = topic
            return .success(resolved)
        case let .some(value):
            state.link.inboundAliases[value] = publish.topic
            return .success(publish)
        }
    }

    private static func deliver(_ publish: Publish, _ state: inout ClientState) -> [ClientCommand] {
        switch publish.delivery {
        case .atMostOnce:
            return [.emit(.message(publish))]
        case let .atLeastOnce(identifier):
            return [.emit(.message(publish))] + send(.pubAck(.success(identifier)), &state)
        case let .exactlyOnce(identifier) where state.receivedQoS2.contains(identifier):
            return send(.pubRec(.success(identifier)), &state)
        case .exactlyOnce where state.receivedQoS2.count >= state.receiveMaximum:
            return abort(.receiveMaximumExceeded, .protocolViolation(.receiveMaximumExceeded), &state)
        case let .exactlyOnce(identifier):
            state.receivedQoS2.insert(identifier)
            return [.emit(.message(publish))] + send(.pubRec(.success(identifier)), &state)
        }
    }

    private static func release(_ ack: Acknowledgement, _ state: inout ClientState) -> [ClientCommand] {
        let known = state.receivedQoS2.remove(ack.packetIdentifier) != nil
        let reason: ReasonCode = known || state.options.version == .v3_1_1 ? .success : .packetIdentifierNotFound
        return send(.pubComp(Acknowledgement(packetIdentifier: ack.packetIdentifier, reasonCode: reason, properties: [])), &state)
    }

    // MARK: Acknowledgements

    private static func acknowledge(_ ack: Acknowledgement, _ type: PacketType, _ state: inout ClientState) -> [ClientCommand] {
        let identifier = ack.packetIdentifier
        switch (type, state.stage(identifier)) {
        case let (.pubAck, .awaitingPubAck(publish)),
             let (.pubComp, .awaitingPubComp(publish)):
            state.remove(identifier)
            return [.emit(.published(publish, ack))] + flush(&state)
        case let (.pubRec, .awaitingPubRec(publish)) where ack.reasonCode.isFailure:
            state.remove(identifier)
            return [.emit(.published(publish, ack))] + flush(&state)
        case let (.pubRec, .awaitingPubRec(publish)),
             let (.pubRec, .awaitingPubComp(publish)):
            state.update(identifier, to: .awaitingPubComp(publish))
            return send(.pubRel(.success(identifier)), &state)
        default:
            return abort(.protocolError, .protocolViolation(.unknownPacketIdentifier(type, identifier)), &state)
        }
    }

    private static func acknowledge(_ ack: SubAck, _ state: inout ClientState) -> [ClientCommand] {
        guard case let .subscribing(subscriptions, _) = state.stage(ack.packetIdentifier) else {
            return abort(.protocolError, .protocolViolation(.unknownPacketIdentifier(.subAck, ack.packetIdentifier)), &state)
        }
        state.remove(ack.packetIdentifier)
        let granted = zip(subscriptions, ack.reasonCodes).filter { !$0.1.isFailure }.map(\.0)
        let grantedFilters = Set(granted.map(\.filter))
        state.subscriptions = state.subscriptions.filter { !grantedFilters.contains($0.filter) } + granted
        return [.emit(.subscribed(subscriptions, ack))]
    }

    private static func acknowledge(_ ack: UnsubAck, _ state: inout ClientState) -> [ClientCommand] {
        guard case let .unsubscribing(filters, _) = state.stage(ack.packetIdentifier) else {
            return abort(.protocolError, .protocolViolation(.unknownPacketIdentifier(.unsubAck, ack.packetIdentifier)), &state)
        }
        state.remove(ack.packetIdentifier)
        let removed = Set(filters)
        state.subscriptions = state.subscriptions.filter { !removed.contains($0.filter) }
        return [.emit(.unsubscribed(filters, ack))]
    }
}

// MARK: - In-flight bookkeeping

extension ClientState {
    func stage(_ identifier: PacketIdentifier) -> InFlight? {
        inFlight.first { $0.identifier == identifier }?.stage
    }

    mutating func remove(_ identifier: PacketIdentifier) {
        inFlight.removeAll { $0.identifier == identifier }
    }

    mutating func update(_ identifier: PacketIdentifier, to stage: InFlight) {
        inFlight = inFlight.map { $0.identifier == identifier ? Entry(identifier: identifier, stage: stage) : $0 }
    }
}
