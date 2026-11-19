// SPDX-License-Identifier: Apache-2.0

/// An MQTT 5 reason code: the outcome carried by acknowledgements, DISCONNECT and AUTH.
///
/// The same byte has different names depending on the packet (`0x00` is "Success" in CONNACK,
/// "Normal disconnection" in DISCONNECT and "Granted QoS 0" in SUBACK), so this is a value type
/// with named constants rather than an enum. Codes below `0x80` are successes, codes from
/// `0x80` up are failures.
///
/// MQTT 3.1.1 has far fewer outcomes; the codec maps them onto these codes on decode and back on
/// encode, so the rest of the library always speaks MQTT 5 vocabulary.
public struct ReasonCode: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
    /// The byte on the wire.
    public let rawValue: UInt8

    /// Wraps any byte. Unknown values are kept so they can be reported and round-tripped.
    /// - Parameter rawValue: The byte on the wire.
    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// `true` for codes `>= 0x80`.
    public var isFailure: Bool { rawValue >= 0x80 }

    /// The hexadecimal byte, e.g. `0x87`.
    public var description: String {
        "0x" + String(rawValue, radix: 16, uppercase: true).leftPadded(to: 2)
    }
}

public extension ReasonCode {
    /// `0x00` Success (CONNACK, PUBACK, PUBREC, PUBREL, PUBCOMP, UNSUBACK, AUTH).
    static let success = ReasonCode(rawValue: 0x00)
    /// `0x00` Normal disconnection (DISCONNECT).
    static let normalDisconnection = ReasonCode(rawValue: 0x00)
    /// `0x00` Granted QoS 0 (SUBACK).
    static let grantedQoS0 = ReasonCode(rawValue: 0x00)
    /// `0x01` Granted QoS 1 (SUBACK).
    static let grantedQoS1 = ReasonCode(rawValue: 0x01)
    /// `0x02` Granted QoS 2 (SUBACK).
    static let grantedQoS2 = ReasonCode(rawValue: 0x02)
    /// `0x04` Disconnect with Will Message (DISCONNECT).
    static let disconnectWithWillMessage = ReasonCode(rawValue: 0x04)
    /// `0x10` No matching subscribers (PUBACK, PUBREC).
    static let noMatchingSubscribers = ReasonCode(rawValue: 0x10)
    /// `0x11` No subscription existed (UNSUBACK).
    static let noSubscriptionExisted = ReasonCode(rawValue: 0x11)
    /// `0x18` Continue authentication (AUTH).
    static let continueAuthentication = ReasonCode(rawValue: 0x18)
    /// `0x19` Re-authenticate (AUTH).
    static let reAuthenticate = ReasonCode(rawValue: 0x19)
    /// `0x80` Unspecified error.
    static let unspecifiedError = ReasonCode(rawValue: 0x80)
    /// `0x81` Malformed Packet.
    static let malformedPacket = ReasonCode(rawValue: 0x81)
    /// `0x82` Protocol Error.
    static let protocolError = ReasonCode(rawValue: 0x82)
    /// `0x83` Implementation specific error.
    static let implementationSpecificError = ReasonCode(rawValue: 0x83)
    /// `0x84` Unsupported Protocol Version (CONNACK).
    static let unsupportedProtocolVersion = ReasonCode(rawValue: 0x84)
    /// `0x85` Client Identifier not valid (CONNACK).
    static let clientIdentifierNotValid = ReasonCode(rawValue: 0x85)
    /// `0x86` Bad User Name or Password (CONNACK).
    static let badUserNameOrPassword = ReasonCode(rawValue: 0x86)
    /// `0x87` Not authorized.
    static let notAuthorized = ReasonCode(rawValue: 0x87)
    /// `0x88` Server unavailable (CONNACK).
    static let serverUnavailable = ReasonCode(rawValue: 0x88)
    /// `0x89` Server busy.
    static let serverBusy = ReasonCode(rawValue: 0x89)
    /// `0x8A` Banned (CONNACK).
    static let banned = ReasonCode(rawValue: 0x8A)
    /// `0x8B` Server shutting down (DISCONNECT).
    static let serverShuttingDown = ReasonCode(rawValue: 0x8B)
    /// `0x8C` Bad authentication method.
    static let badAuthenticationMethod = ReasonCode(rawValue: 0x8C)
    /// `0x8D` Keep Alive timeout (DISCONNECT).
    static let keepAliveTimeout = ReasonCode(rawValue: 0x8D)
    /// `0x8E` Session taken over (DISCONNECT).
    static let sessionTakenOver = ReasonCode(rawValue: 0x8E)
    /// `0x8F` Topic Filter invalid.
    static let topicFilterInvalid = ReasonCode(rawValue: 0x8F)
    /// `0x90` Topic Name invalid.
    static let topicNameInvalid = ReasonCode(rawValue: 0x90)
    /// `0x91` Packet Identifier in use.
    static let packetIdentifierInUse = ReasonCode(rawValue: 0x91)
    /// `0x92` Packet Identifier not found.
    static let packetIdentifierNotFound = ReasonCode(rawValue: 0x92)
    /// `0x93` Receive Maximum exceeded.
    static let receiveMaximumExceeded = ReasonCode(rawValue: 0x93)
    /// `0x94` Topic Alias invalid.
    static let topicAliasInvalid = ReasonCode(rawValue: 0x94)
    /// `0x95` Packet too large.
    static let packetTooLarge = ReasonCode(rawValue: 0x95)
    /// `0x96` Message rate too high.
    static let messageRateTooHigh = ReasonCode(rawValue: 0x96)
    /// `0x97` Quota exceeded.
    static let quotaExceeded = ReasonCode(rawValue: 0x97)
    /// `0x98` Administrative action.
    static let administrativeAction = ReasonCode(rawValue: 0x98)
    /// `0x99` Payload format invalid.
    static let payloadFormatInvalid = ReasonCode(rawValue: 0x99)
    /// `0x9A` Retain not supported.
    static let retainNotSupported = ReasonCode(rawValue: 0x9A)
    /// `0x9B` QoS not supported.
    static let qosNotSupported = ReasonCode(rawValue: 0x9B)
    /// `0x9C` Use another server.
    static let useAnotherServer = ReasonCode(rawValue: 0x9C)
    /// `0x9D` Server moved.
    static let serverMoved = ReasonCode(rawValue: 0x9D)
    /// `0x9E` Shared Subscriptions not supported.
    static let sharedSubscriptionsNotSupported = ReasonCode(rawValue: 0x9E)
    /// `0x9F` Connection rate exceeded.
    static let connectionRateExceeded = ReasonCode(rawValue: 0x9F)
    /// `0xA0` Maximum connect time.
    static let maximumConnectTime = ReasonCode(rawValue: 0xA0)
    /// `0xA1` Subscription Identifiers not supported.
    static let subscriptionIdentifiersNotSupported = ReasonCode(rawValue: 0xA1)
    /// `0xA2` Wildcard Subscriptions not supported.
    static let wildcardSubscriptionsNotSupported = ReasonCode(rawValue: 0xA2)

    /// The SUBACK code granting `qos`.
    /// - Parameter qos: The granted maximum QoS.
    /// - Returns: `grantedQoS0`, `grantedQoS1` or `grantedQoS2`.
    static func granted(_ qos: QoS) -> ReasonCode {
        ReasonCode(rawValue: qos.rawValue)
    }
}

// MARK: - MQTT 3.1.1 mappings

extension ReasonCode {
    /// The MQTT 3.1.1 CONNACK return codes, in order (index = return code).
    static let connectReturnCodes: [ReasonCode] = [
        .success, .unsupportedProtocolVersion, .clientIdentifierNotValid,
        .serverUnavailable, .badUserNameOrPassword, .notAuthorized,
    ]

    /// Maps an MQTT 3.1.1 CONNACK return code onto its MQTT 5 reason code.
    static func fromConnectReturnCode(_ code: UInt8) -> ReasonCode? {
        connectReturnCodes[safe: Int(code)]
    }

    /// The MQTT 3.1.1 CONNACK return code for this reason, when one exists.
    var connectReturnCode: UInt8? {
        ReasonCode.connectReturnCodes.firstIndex(of: self).map(UInt8.init)
    }

    /// The MQTT 3.1.1 SUBACK return code: granted QoS codes are kept, every failure becomes `0x80`.
    var subAckReturnCode: UInt8 {
        isFailure ? 0x80 : rawValue
    }
}

private extension String {
    func leftPadded(to width: Int) -> String {
        String(repeating: "0", count: max(0, width - count)) + self
    }
}
