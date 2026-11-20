// SPDX-License-Identifier: Apache-2.0

import FP
import MQTT

// MARK: - Application requests

extension ClientMachine {
    /// Handles a request: performed now when connected and nothing is waiting ahead of it,
    /// queued otherwise (DISCONNECT always goes straight through).
    static func perform(_ request: ClientRequest, _ state: inout ClientState) -> [ClientCommand] {
        // Extended authentication happens before CONNACK: AUTH replies cannot wait for it.
        if case .authenticate = request, case .awaitingConnAck = state.phase {
            return performNow(request, &state)
        }
        guard case .connected = state.phase else {
            state.queued.append(request)
            return []
        }
        if case .disconnect = request {
            return performNow(request, &state)
        }
        guard state.queued.isEmpty, !waitsForSlot(request, state) else {
            state.queued.append(request)
            return flush(&state)
        }
        return performNow(request, &state)
    }

    private static func performNow(_ request: ClientRequest, _ state: inout ClientState) -> [ClientCommand] {
        switch request {
        case let .publish(message):
            return publish(message, &state)
        case let .subscribe(subscriptions, properties):
            return validateSubscribe(subscriptions, properties, state)
                .map { [.emit(.rejected(request, $0))] } ?? subscribe(subscriptions, properties: properties, &state)
        case let .unsubscribe(filters, properties):
            return unsubscribe(filters, properties: properties, &state)
        case let .authenticate(auth):
            return send(.auth(auth), &state)
        case let .disconnect(disconnect):
            let close = state.connection.map { [ClientCommand.close($0)] } ?? []
            let notice = send(.disconnect(disconnect), &state)
            return end(&state, notice + [.emit(.disconnected(disconnect, byServer: false))] + close + [.finish])
        }
    }

    /// Sends queued requests, in order, until one has to keep waiting for a Receive Maximum slot.
    static func flush(_ state: inout ClientState) -> [ClientCommand] {
        guard case .connected = state.phase, let next = state.queued.first, !waitsForSlot(next, state) else { return [] }
        state.queued.removeFirst()
        let commands = performNow(next, &state)
        return commands + flush(&state)
    }

    private static func waitsForSlot(_ request: ClientRequest, _ state: ClientState) -> Bool {
        guard case let .publish(message) = request, message.qos != .atMostOnce else { return false }
        return state.inFlightPublishes >= state.link.server.receiveMaximum
    }

    // MARK: PUBLISH

    private static func publish(_ message: OutgoingMessage, _ state: inout ClientState) -> [ClientCommand] {
        let server = state.link.server
        let rejection: RequestRejection? = message.qos > server.maximumQoS ? .qosNotSupported(maximum: server.maximumQoS)
            : message.retain && !server.retainAvailable ? .retainNotSupported
            : nil
        if let rejection {
            return [.emit(.rejected(.publish(message), rejection))]
        }
        let draft = Publish(
            topic: message.topic,
            payload: message.payload,
            delivery: .make(message.qos, identifier: .first),
            retain: message.retain,
            duplicate: false,
            properties: message.properties
        )
        if let rejection = sizeRejection(.publish(draft), state) {
            return [.emit(.rejected(.publish(message), rejection))]
        }
        guard message.qos != .atMostOnce else {
            return sendPublish(withDelivery(draft, .atMostOnce), &state)
        }
        return withIdentifier(&state) { identifier, state in
            let publish = withDelivery(draft, .make(message.qos, identifier: identifier))
            state.inFlight.append(ClientState.Entry(
                identifier: identifier,
                stage: message.qos == .atLeastOnce ? .awaitingPubAck(publish) : .awaitingPubRec(publish)
            ))
            return sendPublish(publish, &state)
        }
    }

    private static func withDelivery(_ publish: Publish, _ delivery: Delivery) -> Publish {
        var updated = publish
        updated.delivery = delivery
        return updated
    }

    /// Sends a PUBLISH, replacing its topic with a topic alias when the server allows aliases
    /// (the stored in-flight copy keeps the full topic, so resends work on any connection).
    static func sendPublish(_ publish: Publish, _ state: inout ClientState) -> [ClientCommand] {
        let maximum = state.link.server.topicAliasMaximum
        let hasAlias = publish.properties.contains { if case .topicAlias = $0 { true } else { false } }
        guard state.options.version == .v5, maximum > 0, !hasAlias else { return send(.publish(publish), &state) }
        var aliased = publish
        if let alias = state.link.outboundAliases[publish.topic] {
            aliased.topic = TopicName(rawValue: "") ?? publish.topic
            aliased.properties.append(.topicAlias(alias))
        } else if state.link.outboundAliases.count < Int(maximum) {
            let alias = UInt16(state.link.outboundAliases.count + 1)
            state.link.outboundAliases[publish.topic] = alias
            aliased.properties.append(.topicAlias(alias))
        }
        return send(.publish(aliased), &state)
    }

    // MARK: SUBSCRIBE / UNSUBSCRIBE

    private static func validateSubscribe(
        _ subscriptions: [Subscription],
        _ properties: [Property],
        _ state: ClientState
    ) -> RequestRejection? {
        let server = state.link.server
        let filters = subscriptions.map(\.filter.rawValue)
        let wildcard = filters.contains { $0.contains("+") || $0.contains("#") }
        let shared = filters.contains { $0.hasPrefix("$share/") }
        let identified = properties.contains { if case .subscriptionIdentifier = $0 { true } else { false } }
        return wildcard && !server.wildcardSubscriptionAvailable ? .wildcardSubscriptionsNotSupported
            : shared && !server.sharedSubscriptionAvailable ? .sharedSubscriptionsNotSupported
            : identified && !server.subscriptionIdentifierAvailable ? .subscriptionIdentifiersNotSupported
            : sizeRejection(.subscribe(Subscribe(packetIdentifier: .first, subscriptions: subscriptions, properties: properties)), state)
    }

    static func subscribe(_ subscriptions: [Subscription], properties: [Property], _ state: inout ClientState) -> [ClientCommand] {
        withIdentifier(&state) { identifier, state in
            state.inFlight.append(ClientState.Entry(identifier: identifier, stage: .subscribing(subscriptions, properties: properties)))
            return send(.subscribe(Subscribe(packetIdentifier: identifier, subscriptions: subscriptions, properties: properties)), &state)
        }
    }

    private static func unsubscribe(_ filters: [TopicFilter], properties: [Property], _ state: inout ClientState) -> [ClientCommand] {
        let draft = Packet.unsubscribe(Unsubscribe(packetIdentifier: .first, filters: filters, properties: properties))
        if let rejection = sizeRejection(draft, state) {
            return [.emit(.rejected(.unsubscribe(filters, properties: properties), rejection))]
        }
        return withIdentifier(&state) { identifier, state in
            state.inFlight.append(ClientState.Entry(identifier: identifier, stage: .unsubscribing(filters, properties: properties)))
            return send(.unsubscribe(Unsubscribe(packetIdentifier: identifier, filters: filters, properties: properties)), &state)
        }
    }

    // MARK: Helpers

    /// Why `packet` cannot be sent: it does not encode, or exceeds the server's Maximum Packet Size.
    private static func sizeRejection(_ packet: Packet, _ state: ClientState) -> RequestRejection? {
        switch packet.encode(for: state.options.version) {
        case let .failure(error):
            .encoding(error)
        case let .success(bytes):
            state.link.server.maximumPacketSize.flatMap { bytes.count > $0 ? .packetTooLarge(size: bytes.count, maximum: $0) : nil }
        }
    }

    /// Reserves the next free packet identifier and runs `body` with it.
    private static func withIdentifier(
        _ state: inout ClientState,
        _ body: (PacketIdentifier, inout ClientState) -> [ClientCommand]
    ) -> [ClientCommand] {
        let used = Set(state.inFlight.map(\.identifier))
        let candidates = Swift.sequence(first: state.nextIdentifier, next: \.next).prefix(Int(UInt16.max))
        guard let identifier = candidates.first(where: { !used.contains($0) }) else {
            return end(&state, (state.connection.map { [.close($0)] } ?? []) + [.fail(.packetIdentifiersExhausted)])
        }
        state.nextIdentifier = identifier.next
        return body(identifier, &state)
    }
}
