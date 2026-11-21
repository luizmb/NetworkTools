// SPDX-License-Identifier: Apache-2.0

import FP
import MQTT
import MQTTClient

/// Which way a bridge rule forwards messages.
public enum BridgeDirection: Sendable, Hashable {
    /// From the local broker to the remote one.
    case outbound
    /// From the remote broker to the local one.
    case inbound
    /// Both ways.
    case both
}

/// One forwarding rule, in the spirit of Mosquitto's `topic pattern direction qos local-prefix remote-prefix`.
///
/// `filter` is matched against topics **without** their prefix. A message on the local broker at
/// `localPrefix + topic` is forwarded to `remotePrefix + topic`, and the other way round.
public struct BridgeRule: Sendable, Hashable {
    /// The topics to forward (relative to the prefixes).
    public var filter: TopicFilter
    /// Which way to forward.
    public var direction: BridgeDirection
    /// The highest QoS used to subscribe and forward.
    public var qos: QoS
    /// The prefix of these topics on the local broker (may be empty).
    public var localPrefix: String
    /// The prefix of these topics on the remote broker (may be empty).
    public var remotePrefix: String

    /// Creates a rule.
    public init(filter: TopicFilter, direction: BridgeDirection, qos: QoS, localPrefix: String, remotePrefix: String) {
        self.filter = filter
        self.direction = direction
        self.qos = qos
        self.localPrefix = localPrefix
        self.remotePrefix = remotePrefix
    }
}

/// One side of a bridge.
public enum BridgeSide: Sendable, Hashable {
    /// The local broker.
    case local
    /// The remote broker.
    case remote

    /// The other side.
    public var opposite: BridgeSide {
        self == .local ? .remote : .local
    }
}

/// What a bridge reports.
public enum BridgeEvent: Sendable, Hashable {
    /// Something happened to one side's client session.
    case session(BridgeSide, ClientEvent)
    /// A message was forwarded from `from` to the other side, under `topic` there.
    case forwarded(from: BridgeSide, Publish, as: TopicName)
}

/// Why a bridge stopped.
public enum BridgeError: Error, Sendable, Hashable {
    /// One side's session failed.
    case session(BridgeSide, ClientError)
}

/// What the bridge asks for.
public enum BridgeOutput: Sendable, Hashable {
    /// Send a request to one side's session.
    case request(BridgeSide, ClientRequest)
    /// Report an event.
    case emit(BridgeEvent)
}

/// What a bridge remembers: which sides have been subscribed, and what it forwarded recently
/// (to drop the echo of its own messages on MQTT 3.1.1, which has no No Local).
public struct BridgeState: Sendable, Hashable {
    /// The forwarding rules.
    public let rules: [BridgeRule]
    /// The protocol version of each side (No Local exists only in MQTT 5).
    public let versions: [BridgeSide: ProtocolVersion]
    /// Sides whose subscriptions were sent.
    public internal(set) var subscribed: Set<BridgeSide>
    /// Recently forwarded messages, by the side they were sent to.
    public internal(set) var recent: [Forwarded]

    /// A forwarded message, remembered to recognise its echo.
    public struct Forwarded: Sendable, Hashable {
        /// The side it was sent to.
        public var side: BridgeSide
        /// Its topic there.
        public var topic: TopicName
        /// Its payload.
        public var payload: [UInt8]
    }

    /// How many forwarded messages are remembered for echo detection.
    static let memory = 64

    /// A bridge that has not subscribed anywhere yet.
    public static func initial(rules: [BridgeRule], local: ProtocolVersion, remote: ProtocolVersion) -> BridgeState {
        BridgeState(rules: rules, versions: [.local: local, .remote: remote], subscribed: [], recent: [])
    }
}

/// The bridge as a pure state machine: session events in, requests for the other session out.
public enum BridgeMachine {
    /// One transition.
    /// - Parameters:
    ///   - side: The session the event comes from.
    ///   - event: What happened there.
    /// - Returns: A state step producing the outputs.
    public static func step(_ side: BridgeSide, _ event: ClientEvent) -> Stateful<BridgeState, [BridgeOutput]> {
        Stateful { state in
            let report = BridgeOutput.emit(.session(side, event))
            switch event {
            case .connected where !state.subscribed.contains(side):
                state.subscribed.insert(side)
                return [report] + subscriptions(on: side, state)
            case let .message(publish):
                return forward(publish, from: side, &state)
            default:
                return [report]
            }
        }
    }

    /// The SUBSCRIBE a side needs: every rule that forwards away from it, under that side's prefix.
    static func subscriptions(on side: BridgeSide, _ state: BridgeState) -> [BridgeOutput] {
        let noLocal = state.versions[side] == .v5
        let subscriptions = state.rules
            .filter { forwards($0, from: side) }
            .compactMap { rule in
                TopicFilter(rawValue: prefix(rule, side) + rule.filter.rawValue).map { filter in
                    Subscription(
                        filter: filter,
                        options: SubscriptionOptions(
                            qos: rule.qos,
                            noLocal: noLocal,
                            retainAsPublished: true,
                            retainHandling: .sendOnSubscribe
                        )
                    )
                }
            }
        return subscriptions.isEmpty ? [] : [.request(side, .subscribe(subscriptions, properties: []))]
    }

    private static func forward(_ publish: Publish, from side: BridgeSide, _ state: inout BridgeState) -> [BridgeOutput] {
        let echo = BridgeState.Forwarded(side: side, topic: publish.topic, payload: publish.payload)
        if let index = state.recent.firstIndex(of: echo) {
            state.recent.remove(at: index)
            return []
        }
        let target = side.opposite
        let destinations = state.rules
            .filter { forwards($0, from: side) }
            .compactMap { rule -> (BridgeRule, TopicName)? in
                let local = prefix(rule, side)
                guard publish.topic.rawValue.hasPrefix(local),
                      let relative = TopicName(rawValue: String(publish.topic.rawValue.dropFirst(local.count))),
                      rule.filter.matches(relative),
                      let mapped = TopicName(rawValue: prefix(rule, target) + relative.rawValue) else { return nil }
                return (rule, mapped)
            }
        guard let (rule, topic) = destinations.first else { return [] }
        let message = OutgoingMessage(
            topic: topic,
            payload: publish.payload,
            qos: min(rule.qos, publish.delivery.qos),
            retain: publish.retain,
            properties: publish.properties.filter { property in
                switch property {
                case .topicAlias,
                     .subscriptionIdentifier: false
                default: true
                }
            }
        )
        if state.versions[target] != .v5 || state.versions[side] != .v5 {
            state
                .recent = Array((state.recent + [BridgeState.Forwarded(side: target, topic: topic, payload: publish.payload)])
                    .suffix(BridgeState.memory))
        }
        return [.request(target, .publish(message)), .emit(.forwarded(from: side, publish, as: topic))]
    }

    private static func forwards(_ rule: BridgeRule, from side: BridgeSide) -> Bool {
        switch (rule.direction, side) {
        case (.both, _),
             (.outbound, .local),
             (.inbound, .remote): true
        case (.outbound, .remote),
             (.inbound, .local): false
        }
    }

    private static func prefix(_ rule: BridgeRule, _ side: BridgeSide) -> String {
        side == .local ? rule.localPrefix : rule.remotePrefix
    }
}
