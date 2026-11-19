// SPDX-License-Identifier: Apache-2.0

/// Quality of Service: the delivery guarantee of an application message.
public enum QoS: UInt8, Sendable, Hashable, CaseIterable, Comparable {
    /// Fire and forget. No acknowledgement.
    case atMostOnce = 0
    /// Acknowledged with PUBACK; may be delivered more than once.
    case atLeastOnce = 1
    /// Four-step PUBREC / PUBREL / PUBCOMP handshake; delivered exactly once.
    case exactlyOnce = 2

    /// Orders QoS levels by strength of guarantee.
    public static func < (lhs: QoS, rhs: QoS) -> Bool { lhs.rawValue < rhs.rawValue }
}
