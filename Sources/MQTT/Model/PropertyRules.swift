// SPDX-License-Identifier: Apache-2.0

/// Where a property list appears: each place allows a different set of properties.
public enum PropertyContext: Sendable, Hashable {
    /// CONNECT.
    case connect
    /// The Will properties inside CONNECT.
    case will
    /// CONNACK.
    case connAck
    /// PUBLISH.
    case publish
    /// PUBACK, PUBREC, PUBREL, PUBCOMP.
    case acknowledgement
    /// SUBSCRIBE.
    case subscribe
    /// SUBACK.
    case subAck
    /// UNSUBSCRIBE.
    case unsubscribe
    /// UNSUBACK.
    case unsubAck
    /// DISCONNECT.
    case disconnect
    /// AUTH.
    case auth
}

/// How a property list breaks the MQTT 5 rules.
public enum PropertyViolation: Error, Sendable, Hashable {
    /// The property may not appear in this packet.
    case notAllowed(identifier: UInt8, in: PropertyContext)
    /// The property appears more than once where only one is allowed.
    case duplicate(identifier: UInt8)
    /// The property's value is out of range (a 0/1 flag with another value, a zero maximum, …).
    case invalidValue(identifier: UInt8)
}

/// The MQTT 5 rules for property lists (section 2.2.2 and each packet's "Properties" section):
/// which properties a packet allows, which may repeat, and which values are valid.
public enum PropertyRules {
    /// Checks a property list against the rules for its context.
    /// - Parameters:
    ///   - properties: The list, in wire order.
    ///   - context: Where it appears.
    /// - Returns: The list unchanged, or the first violation.
    public static func validate(_ properties: [Property], in context: PropertyContext) -> Result<[Property], PropertyViolation> {
        properties
            .reduce(Result<Set<UInt8>, PropertyViolation>.success([])) { seen, property in
                seen.flatMap { check(property, in: context, seen: $0) }
            }
            .map { _ in properties }
    }

    /// Checks one property, given the identifiers already seen; returns them with this one added.
    private static func check(
        _ property: Property,
        in context: PropertyContext,
        seen: Set<UInt8>
    ) -> Result<Set<UInt8>, PropertyViolation> {
        let identifier = property.identifier
        let repeated = seen.contains(identifier) && !repeatableIdentifiers(context).contains(identifier)
        return !allowedIdentifiers(context).contains(identifier) ? .failure(.notAllowed(identifier: identifier, in: context))
            : repeated ? .failure(.duplicate(identifier: identifier))
            : !isValid(property) ? .failure(.invalidValue(identifier: identifier))
            : .success(seen.union([identifier]))
    }

    static func allowedIdentifiers(_ context: PropertyContext) -> Set<UInt8> {
        let user: UInt8 = 0x26
        let reason: UInt8 = 0x1F
        return switch context {
        case .connect: [0x11, 0x15, 0x16, 0x17, 0x19, 0x21, 0x22, user, 0x27]
        case .will: [0x01, 0x02, 0x03, 0x08, 0x09, 0x18, user]
        case .connAck:
            [0x11, 0x12, 0x13, 0x15, 0x16, 0x1A, 0x1C, reason, 0x21, 0x22, 0x24, 0x25, user, 0x27, 0x28, 0x29, 0x2A]
        case .publish: [0x01, 0x02, 0x03, 0x08, 0x09, 0x0B, 0x23, user]
        case .acknowledgement,
             .subAck,
             .unsubAck: [reason, user]
        case .subscribe: [0x0B, user]
        case .unsubscribe: [user]
        case .disconnect: [0x11, 0x1C, reason, user]
        case .auth: [0x15, 0x16, reason, user]
        }
    }

    static func repeatableIdentifiers(_ context: PropertyContext) -> Set<UInt8> {
        context == .publish ? [0x26, 0x0B] : [0x26]
    }

    static func isValid(_ property: Property) -> Bool {
        switch property {
        case let .payloadFormatIndicator(value),
             let .requestProblemInformation(value),
             let .requestResponseInformation(value),
             let .maximumQoS(value),
             let .retainAvailable(value),
             let .wildcardSubscriptionAvailable(value),
             let .subscriptionIdentifierAvailable(value),
             let .sharedSubscriptionAvailable(value):
            value <= 1
        case let .receiveMaximum(value),
             let .topicAlias(value):
            value > 0
        case let .maximumPacketSize(value):
            value > 0
        case let .subscriptionIdentifier(value):
            (1...268_435_455).contains(value)
        default:
            true
        }
    }
}
