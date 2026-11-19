// SPDX-License-Identifier: Apache-2.0

/// The MQTT protocol revision spoken on a connection.
///
/// The raw value is the "protocol level" byte carried in the CONNECT packet. A client picks
/// the version when it connects; a broker learns it from the CONNECT it decodes. Every other
/// packet is then encoded and decoded for that version.
///
/// MQTT 3.1 (`MQIsdp`, level 3) is not supported.
public enum ProtocolVersion: UInt8, Sendable, Hashable, CaseIterable {
    /// MQTT 3.1.1 (OASIS Standard, 2014). Protocol level 4.
    case v3_1_1 = 4
    /// MQTT 5.0 (OASIS Standard, 2019). Protocol level 5.
    case v5 = 5
}
