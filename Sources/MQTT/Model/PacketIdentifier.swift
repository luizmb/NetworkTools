// SPDX-License-Identifier: Apache-2.0

/// The non-zero 16-bit identifier that pairs a request with its acknowledgement
/// (PUBLISH with QoS > 0, SUBSCRIBE, UNSUBSCRIBE and their ACKs).
public struct PacketIdentifier: RawRepresentable, Sendable, Hashable, Comparable, CustomStringConvertible {
    /// The identifier's value, never zero.
    public let rawValue: UInt16

    /// Wraps a value, rejecting zero (which the protocol reserves).
    /// - Parameter rawValue: The identifier's value.
    public init?(rawValue: UInt16) {
        guard rawValue != 0 else { return nil }
        self.rawValue = rawValue
    }

    /// The first identifier: `1`.
    public static let first = PacketIdentifier(unchecked: 1)

    /// The identifier after this one, wrapping from `65535` back to `1`.
    public var next: PacketIdentifier {
        PacketIdentifier(unchecked: rawValue == .max ? 1 : rawValue + 1)
    }

    /// Orders identifiers by value.
    public static func < (lhs: PacketIdentifier, rhs: PacketIdentifier) -> Bool { lhs.rawValue < rhs.rawValue }

    /// The identifier's value.
    public var description: String { String(rawValue) }

    private init(unchecked rawValue: UInt16) {
        self.rawValue = rawValue
    }
}
