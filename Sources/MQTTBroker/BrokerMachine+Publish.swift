// SPDX-License-Identifier: Apache-2.0

import FP
import MQTT

// MARK: - Inbound PUBLISH

extension BrokerMachine {
    static func inbound(
        _ publish: Publish,
        from client: String,
        on id: ConnectionID,
        _ policy: BrokerPolicy,
        _ state: inout BrokerState
    ) -> [BrokerCommand] {
        let options = state.options
        guard publish.delivery.qos <= options.maximumQoS else { return disconnect(id, .qosNotSupported, &state) }
        guard !publish.retain || options.retainAvailable else { return disconnect(id, .retainNotSupported, &state) }
        guard let resolved = resolveAlias(publish, on: id, &state) else { return disconnect(id, .topicAliasInvalid, &state) }
        let allowed = policy.mayPublish(client, resolved.topic)
        switch resolved.delivery {
        case .atMostOnce:
            return allowed ? distribute(resolved, from: client, &state) : []
        case let .atLeastOnce(identifier):
            let reason: ReasonCode = allowed ? .success : .notAuthorized
            let ack = Acknowledgement(packetIdentifier: identifier, reasonCode: ackReason(reason, on: id, state), properties: [])
            return (allowed ? distribute(resolved, from: client, &state) : []) + send(.pubAck(ack), on: id, state)
        case let .exactlyOnce(identifier) where state.sessions[client]?.receivedQoS2.contains(identifier) == true:
            return send(.pubRec(.success(identifier)), on: id, state)
        case .exactlyOnce where (state.sessions[client]?.receivedQoS2.count ?? 0) >= Int(options.receiveMaximum):
            return disconnect(id, .receiveMaximumExceeded, &state)
        case let .exactlyOnce(identifier):
            let ack = Acknowledgement(
                packetIdentifier: identifier,
                reasonCode: ackReason(allowed ? .success : .notAuthorized, on: id, state),
                properties: []
            )
            if allowed { state.sessions[client]?.receivedQoS2.insert(identifier) }
            return (allowed ? distribute(resolved, from: client, &state) : []) + send(.pubRec(ack), on: id, state)
        }
    }

    /// MQTT 3.1.1 acknowledgements carry no reason: a refused message is acknowledged as success.
    private static func ackReason(_ reason: ReasonCode, on id: ConnectionID, _ state: BrokerState) -> ReasonCode {
        state.links[id]?.version == .v5 ? reason : .success
    }

    /// Replaces a client's Topic Alias by its topic; `nil` when the alias is invalid.
    private static func resolveAlias(_ publish: Publish, on id: ConnectionID, _ state: inout BrokerState) -> Publish? {
        let alias = publish.properties.lazy.compactMap { property -> UInt16? in
            guard case let .topicAlias(value) = property else { return nil }
            return value
        }.first
        var resolved = publish
        resolved.properties.removeAll { if case .topicAlias = $0 { true } else { false } }
        switch alias {
        case .none:
            return publish.topic.rawValue.isEmpty ? nil : resolved
        case let .some(value) where value == 0 || value > state.options.topicAliasMaximum:
            return nil
        case let .some(value) where publish.topic.rawValue.isEmpty:
            guard let topic = state.links[id]?.inboundAliases[value] else { return nil }
            resolved.topic = topic
            return resolved
        case let .some(value):
            state.links[id]?.inboundAliases[value] = publish.topic
            return resolved
        }
    }

    static func release(_ ack: Acknowledgement, client: String, on id: ConnectionID, _ state: inout BrokerState) -> [BrokerCommand] {
        let known = state.sessions[client]?.receivedQoS2.remove(ack.packetIdentifier) != nil
        let reason = known ? ReasonCode.success : ackReason(.packetIdentifierNotFound, on: id, state)
        return send(.pubComp(Acknowledgement(packetIdentifier: ack.packetIdentifier, reasonCode: reason, properties: [])), on: id, state)
    }

    // MARK: Outbound acknowledgements

    /// PUBACK (QoS 1) or PUBCOMP (QoS 2) from a client: the delivery is done.
    static func completed(_ ack: Acknowledgement, client: String, _ state: inout BrokerState) -> [BrokerCommand] {
        state.sessions[client]?.inFlight.removeAll { $0.identifier == ack.packetIdentifier }
        return drain(client, &state)
    }

    /// PUBREC from a client: release the message (or drop it if the client refused it).
    static func received(_ ack: Acknowledgement, client: String, _ state: inout BrokerState) -> [BrokerCommand] {
        guard let id = state.sessions[client]?.connection else { return [] }
        guard !ack.reasonCode.isFailure else { return completed(ack, client: client, &state) }
        let inFlight = state.sessions[client]?.inFlight ?? []
        state.sessions[client]?.inFlight = inFlight.map { delivery in
            var updated = delivery
            if delivery.identifier == ack.packetIdentifier { updated.released = true }
            return updated
        }
        return send(.pubRel(.success(ack.packetIdentifier)), on: id, state)
    }

    // MARK: - Distribution

    /// Stores retained messages and delivers a message to every matching subscription, once per
    /// session, at the highest granted QoS, with all matching Subscription Identifiers.
    static func distribute(_ publish: Publish, from publisher: String?, _ state: inout BrokerState) -> [BrokerCommand] {
        let stored = BrokerState.Stored(publish: publish, receivedAt: state.now)
        if publish.retain, state.options.retainAvailable {
            state.retained[publish.topic] = publish.payload.isEmpty ? nil : stored
        }
        let direct = state.sessions.keys.sorted().compactMap { client -> (String, Publish)? in
            outgoing(publish, to: client, from: publisher, state).map { (client, $0) }
        }
        let shared = sharedTargets(publish, &state)
        return [.emit(.published(publish, from: publisher))]
            + (direct + shared).flatMap { client, message in enqueue(message, receivedAt: state.now, to: client, &state) }
    }

    /// The message as this session receives it through its non-shared subscriptions, if any match.
    private static func outgoing(_ publish: Publish, to client: String, from publisher: String?, _ state: BrokerState) -> Publish? {
        let matches = (state.sessions[client]?.subscriptions ?? [:])
            .filter { filter, subscribed in
                !filter.rawValue.hasPrefix("$share/") && filter.matches(publish.topic)
                    && !(subscribed.options.noLocal && client == publisher)
            }
            .map(\.value)
        guard !matches.isEmpty else { return nil }
        return forward(
            publish,
            qos: matches.map(\.options.qos).max() ?? .atMostOnce,
            retainAsPublished: matches.contains { $0.options.retainAsPublished },
            identifiers: matches.compactMap(\.identifier).sorted()
        )
    }

    /// One receiver per shared group (`$share/group/filter`), chosen round robin.
    private static func sharedTargets(_ publish: Publish, _ state: inout BrokerState) -> [(String, Publish)] {
        let members = state.sessions.keys.sorted().flatMap { client in
            (state.sessions[client]?.subscriptions ?? [:]).compactMap { filter, subscribed -> SharedMember? in
                SharedFilter.parse(filter).flatMap { $0.filter.matches(publish.topic) ? (filter, client, subscribed) : nil }
            }
        }
        let groups = Dictionary(grouping: members, by: \.0)
        return groups.keys.sorted { $0.rawValue < $1.rawValue }.compactMap { group in
            let candidates = groups[group] ?? []
            let connected = candidates.filter { state.sessions[$0.1]?.connection != nil }
            let pool = connected.isEmpty ? candidates : connected
            guard !pool.isEmpty else { return nil }
            let cursor = state.sharedCursor[group] ?? 0
            state.sharedCursor[group] = cursor + 1
            let (_, client, subscribed) = pool[cursor % pool.count]
            return (client, forward(
                publish,
                qos: subscribed.options.qos,
                retainAsPublished: false,
                identifiers: subscribed.identifier.map { [$0] } ?? []
            ))
        }
    }

    /// The forwarded copy: QoS capped by the subscription, RETAIN cleared unless Retain As
    /// Published, client-specific properties replaced by the matching Subscription Identifiers.
    private static func forward(_ publish: Publish, qos: QoS, retainAsPublished: Bool, identifiers: [UInt32]) -> Publish {
        var copy = publish
        copy.delivery = .make(min(publish.delivery.qos, qos), identifier: .first)
        copy.retain = retainAsPublished && publish.retain
        copy.duplicate = false
        copy.properties = publish.properties.filter { property in
            switch property {
            case .topicAlias,
                 .subscriptionIdentifier: false
            default: true
            }
        } + identifiers.map(Property.subscriptionIdentifier)
        return copy
    }

    // MARK: - Delivery to a session

    /// Adds a message to a session's queue and sends what the connection can take now.
    static func enqueue(_ publish: Publish, receivedAt: Duration, to client: String, _ state: inout BrokerState) -> [BrokerCommand] {
        guard var session = state.sessions[client] else { return [] }
        guard session.connection != nil || publish.delivery.qos != .atMostOnce else { return [] }
        session.queued.append(BrokerState.Stored(publish: publish, receivedAt: receivedAt))
        session.queued = Array(session.queued.suffix(state.options.maximumQueuedMessages))
        state.sessions[client] = session
        return drain(client, &state)
    }

    /// Sends queued messages while the client's Receive Maximum allows.
    static func drain(_ client: String, _ state: inout BrokerState) -> [BrokerCommand] {
        guard var session = state.sessions[client], let id = session.connection, let link = state.links[id],
              let next = session.queued.first else { return [] }
        let isQoS0 = next.publish.delivery.qos == .atMostOnce
        guard isQoS0 || session.inFlight.count < link.clientReceiveMaximum else { return [] }
        session.queued.removeFirst()
        guard let message = expiring(next, now: state.now) else {
            state.sessions[client] = session
            return drain(client, &state)
        }
        let size = (try? Packet.publish(message).encode(for: link.version).get().count) ?? Int.max
        guard link.clientMaximumPacketSize.map({ size <= $0 }) ?? true else {
            state.sessions[client] = session
            return drain(client, &state)
        }
        guard !isQoS0 else {
            state.sessions[client] = session
            return send(.publish(message), on: id, state) + drain(client, &state)
        }
        let used = Set(session.inFlight.map(\.identifier))
        let identifier = Swift.sequence(first: session.nextIdentifier, next: \.next).prefix(Int(UInt16.max)).first { !used.contains($0) }
        guard let identifier else {
            session.queued.insert(next, at: 0)
            state.sessions[client] = session
            return []
        }
        var numbered = message
        numbered.delivery = .make(message.delivery.qos, identifier: identifier)
        session.nextIdentifier = identifier.next
        session.inFlight.append(BrokerState.Delivery(identifier: identifier, publish: numbered, released: false))
        state.sessions[client] = session
        return send(.publish(numbered), on: id, state) + drain(client, &state)
    }

    /// The message with its Message Expiry Interval reduced by the time it waited; `nil` if expired.
    private static func expiring(_ stored: BrokerState.Stored, now: Duration) -> Publish? {
        let waited = Int((now - stored.receivedAt).components.seconds)
        let interval = stored.publish.properties.lazy.compactMap { property -> Int? in
            guard case let .messageExpiryInterval(seconds) = property else { return nil }
            return Int(seconds)
        }.first
        guard let interval else { return stored.publish }
        guard interval > waited else { return nil }
        var publish = stored.publish
        publish.properties = publish.properties.map { property in
            if case .messageExpiryInterval = property { .messageExpiryInterval(UInt32(interval - waited)) } else { property }
        }
        return publish
    }
}

/// One member of a shared subscription group: the full filter, the client, its subscription.
typealias SharedMember = (TopicFilter, String, BrokerState.Subscribed)

/// A `$share/{group}/{filter}` subscription, split.
struct SharedFilter {
    let group: String
    let filter: TopicFilter

    static func parse(_ filter: TopicFilter) -> SharedFilter? {
        let parts = filter.rawValue.split(separator: "/", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "$share", !parts[1].isEmpty,
              let inner = TopicFilter(rawValue: String(parts[2])) else { return nil }
        return SharedFilter(group: String(parts[1]), filter: inner)
    }
}
