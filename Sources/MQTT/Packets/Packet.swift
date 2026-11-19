// SPDX-License-Identifier: Apache-2.0

/// An MQTT control packet, any of the fifteen types, in a version-neutral (MQTT 5-shaped) model.
///
/// The model is a superset: MQTT 3.1.1 packets simply leave properties empty and use the
/// success reason codes. The codec (``Packet/encoder(for:)`` / ``Packet/parser(for:)``) decides
/// what each version can carry and fails with a typed error instead of dropping data.
///
/// Every role uses the same model and codec in both directions: a client encodes CONNECT and
/// decodes CONNACK, a broker does the opposite.
public enum Packet: Sendable, Hashable {
    /// Client → server: open a session.
    case connect(Connect)
    /// Server → client: result of CONNECT.
    case connAck(ConnAck)
    /// Either direction: an application message.
    case publish(Publish)
    /// Acknowledges a QoS 1 PUBLISH.
    case pubAck(Acknowledgement)
    /// QoS 2 step 1: PUBLISH received.
    case pubRec(Acknowledgement)
    /// QoS 2 step 2: release the message.
    case pubRel(Acknowledgement)
    /// QoS 2 step 3: delivery complete.
    case pubComp(Acknowledgement)
    /// Client → server: add subscriptions.
    case subscribe(Subscribe)
    /// Server → client: result of SUBSCRIBE.
    case subAck(SubAck)
    /// Client → server: remove subscriptions.
    case unsubscribe(Unsubscribe)
    /// Server → client: result of UNSUBSCRIBE.
    case unsubAck(UnsubAck)
    /// Client → server: keep-alive probe.
    case pingReq
    /// Server → client: keep-alive answer.
    case pingResp
    /// Either direction: the session is ending.
    case disconnect(Disconnect)
    /// Either direction (MQTT 5 only): extended authentication exchange.
    case auth(Auth)

    /// The control packet type.
    public var type: PacketType {
        switch self {
        case .connect: .connect
        case .connAck: .connAck
        case .publish: .publish
        case .pubAck: .pubAck
        case .pubRec: .pubRec
        case .pubRel: .pubRel
        case .pubComp: .pubComp
        case .subscribe: .subscribe
        case .subAck: .subAck
        case .unsubscribe: .unsubscribe
        case .unsubAck: .unsubAck
        case .pingReq: .pingReq
        case .pingResp: .pingResp
        case .disconnect: .disconnect
        case .auth: .auth
        }
    }
}
