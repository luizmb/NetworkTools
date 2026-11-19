// SPDX-License-Identifier: Apache-2.0

// MARK: - DISCONNECT / AUTH

/// DISCONNECT: the session is ending.
public struct Disconnect: Sendable, Hashable {
    /// Why (always ``ReasonCode/normalDisconnection`` in 3.1.1).
    public var reasonCode: ReasonCode
    /// Properties (MQTT 5).
    public var properties: [Property]

    /// Creates a DISCONNECT packet.
    public init(reasonCode: ReasonCode, properties: [Property]) {
        self.reasonCode = reasonCode
        self.properties = properties
    }

    /// A normal disconnection with no properties.
    public static let normal = Disconnect(reasonCode: .normalDisconnection, properties: [])
}

/// AUTH (MQTT 5 only): one step of an extended authentication exchange.
public struct Auth: Sendable, Hashable {
    /// The step's outcome.
    public var reasonCode: ReasonCode
    /// Properties, typically Authentication Method and Data.
    public var properties: [Property]

    /// Creates an AUTH packet.
    public init(reasonCode: ReasonCode, properties: [Property]) {
        self.reasonCode = reasonCode
        self.properties = properties
    }
}
