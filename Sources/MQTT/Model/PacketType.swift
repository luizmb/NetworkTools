// SPDX-License-Identifier: Apache-2.0

/// The control packet type, the high nibble of the first byte of every packet.
public enum PacketType: UInt8, Sendable, Hashable, CaseIterable {
    /// Client request to connect.
    case connect = 1
    /// Connection acknowledgement.
    case connAck = 2
    /// Application message.
    case publish = 3
    /// QoS 1 publish acknowledgement.
    case pubAck = 4
    /// QoS 2 publish received (step 1).
    case pubRec = 5
    /// QoS 2 publish release (step 2).
    case pubRel = 6
    /// QoS 2 publish complete (step 3).
    case pubComp = 7
    /// Subscribe request.
    case subscribe = 8
    /// Subscribe acknowledgement.
    case subAck = 9
    /// Unsubscribe request.
    case unsubscribe = 10
    /// Unsubscribe acknowledgement.
    case unsubAck = 11
    /// Keep-alive ping request.
    case pingReq = 12
    /// Keep-alive ping response.
    case pingResp = 13
    /// Disconnect notification.
    case disconnect = 14
    /// Authentication exchange (MQTT 5 only).
    case auth = 15

    /// The flags nibble this packet type requires, or `nil` for PUBLISH, whose flags carry data.
    var requiredFlags: UInt8? {
        switch self {
        case .publish: nil
        case .pubRel, .subscribe, .unsubscribe: 0b0010
        default: 0
        }
    }
}
