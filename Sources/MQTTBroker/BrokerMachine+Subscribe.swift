// SPDX-License-Identifier: Apache-2.0

import FP
import MQTT

// MARK: - SUBSCRIBE / UNSUBSCRIBE

extension BrokerMachine {
    static func subscribe(
        _ subscribe: Subscribe,
        client: String,
        on id: ConnectionID,
        _ policy: BrokerPolicy,
        _ state: inout BrokerState
    ) -> [BrokerCommand] {
        let identifier = subscribe.properties.lazy.compactMap { property -> UInt32? in
            guard case let .subscriptionIdentifier(value) = property else { return nil }
            return value
        }.first
        guard identifier == nil || state.options.subscriptionIdentifierAvailable else {
            return disconnect(id, .subscriptionIdentifiersNotSupported, &state)
        }
        if subscribe.subscriptions.contains(where: { SharedFilter.parse($0.filter) != nil && $0.options.noLocal }) {
            return disconnect(id, .protocolError, &state)
        }
        let outcomes = subscribe.subscriptions.map { subscription in
            (subscription, grant(subscription, client: client, policy, state))
        }
        let isNew = outcomes.map { subscription, code in
            !code.isFailure && state.sessions[client]?.subscriptions[subscription.filter] == nil
        }
        for (subscription, code) in outcomes where !code.isFailure {
            var options = subscription.options
            options.qos = QoS(rawValue: code.rawValue) ?? .atMostOnce
            state.sessions[client]?.subscriptions[subscription.filter] = BrokerState.Subscribed(options: options, identifier: identifier)
        }
        let ack = SubAck(packetIdentifier: subscribe.packetIdentifier, reasonCodes: outcomes.map(\.1), properties: [])
        let granted = outcomes.filter { !$0.1.isFailure }.map(\.0)
        let retained = zip(outcomes, isNew).flatMap { outcome, new in
            outcome.1.isFailure ? [] : retainedMessages(for: outcome.0, new: new, granted: outcome.1, identifier: identifier, state)
        }
        return send(.subAck(ack), on: id, state)
            + [.emit(.subscribed(clientIdentifier: client, granted))]
            + retained.flatMap { enqueue($0.publish, receivedAt: $0.receivedAt, to: client, &state) }
    }

    /// The SUBACK code for one subscription: the granted QoS, or why it was refused.
    private static func grant(_ subscription: Subscription, client: String, _ policy: BrokerPolicy, _ state: BrokerState) -> ReasonCode {
        let options = state.options
        let shared = SharedFilter.parse(subscription.filter)
        let raw = subscription.filter.rawValue
        let pattern = shared?.filter.rawValue ?? raw
        let wildcard = pattern.contains("+") || pattern.contains("#")
        return raw.hasPrefix("$share/") && shared == nil ? .topicFilterInvalid
            : shared != nil && !options.sharedSubscriptionAvailable ? .sharedSubscriptionsNotSupported
            : wildcard && !options.wildcardSubscriptionAvailable ? .wildcardSubscriptionsNotSupported
            : !policy.maySubscribe(client, subscription.filter) ? .notAuthorized
            : .granted(min(subscription.options.qos, options.maximumQoS))
    }

    /// Retained messages for a new subscription, per its Retain Handling (none for shared ones).
    private static func retainedMessages(
        for subscription: Subscription,
        new: Bool,
        granted: ReasonCode,
        identifier: UInt32?,
        _ state: BrokerState
    ) -> [BrokerState.Stored] {
        let wanted = switch subscription.options.retainHandling {
        case .sendOnSubscribe: true
        case .sendOnNewSubscription: new
        case .doNotSend: false
        }
        guard wanted, SharedFilter.parse(subscription.filter) == nil else { return [] }
        return state.retained.keys.sorted { $0.rawValue < $1.rawValue }.compactMap { topic in
            guard subscription.filter.matches(topic), let stored = state.retained[topic] else { return nil }
            var publish = stored.publish
            publish.delivery = .make(min(publish.delivery.qos, QoS(rawValue: granted.rawValue) ?? .atMostOnce), identifier: .first)
            publish.retain = true
            publish.properties = publish.properties.filter { if case .subscriptionIdentifier = $0 { false } else { true } }
                + (identifier.map { [.subscriptionIdentifier($0)] } ?? [])
            return BrokerState.Stored(publish: publish, receivedAt: stored.receivedAt)
        }
    }

    static func unsubscribe(_ unsubscribe: Unsubscribe, client: String, _ state: inout BrokerState) -> [BrokerCommand] {
        guard let id = state.sessions[client]?.connection else { return [] }
        let codes = unsubscribe.filters.map { filter -> ReasonCode in
            state.sessions[client]?.subscriptions.removeValue(forKey: filter) == nil ? .noSubscriptionExisted : .success
        }
        let version = state.links[id]?.version ?? .v5
        let ack = UnsubAck(packetIdentifier: unsubscribe.packetIdentifier, reasonCodes: version == .v5 ? codes : [], properties: [])
        return send(.unsubAck(ack), on: id, state)
    }
}
