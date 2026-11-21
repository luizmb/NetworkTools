// SPDX-License-Identifier: Apache-2.0

import MQTT
import Testing

@Suite struct PropertyRulesTests {
    @Test func propertyNotAllowedInThePacket() {
        #expect(
            PropertyRules.validate([.topicAlias(1)], in: .connect)
                == .failure(.notAllowed(identifier: 0x23, in: .connect))
        )
    }

    @Test func duplicatesAreRejectedExceptUserProperties() {
        #expect(PropertyRules.validate([.reasonString("a"), .reasonString("b")], in: .disconnect) == .failure(.duplicate(identifier: 0x1F)))
        let users: [Property] = [.userProperty(name: "a", value: "1"), .userProperty(name: "a", value: "2")]
        #expect(PropertyRules.validate(users, in: .disconnect) == .success(users))
    }

    @Test func subscriptionIdentifiersRepeatOnlyInPublish() {
        let identifiers: [Property] = [.subscriptionIdentifier(1), .subscriptionIdentifier(2)]
        #expect(PropertyRules.validate(identifiers, in: .publish) == .success(identifiers))
        #expect(PropertyRules.validate(identifiers, in: .subscribe) == .failure(.duplicate(identifier: 0x0B)))
    }

    @Test(arguments: [
        Property.payloadFormatIndicator(2),
        .maximumQoS(2),
        .receiveMaximum(0),
        .topicAlias(0),
        .maximumPacketSize(0),
        .subscriptionIdentifier(0),
    ])
    func outOfRangeValues(property: Property) {
        let context: PropertyContext = switch property {
        case .payloadFormatIndicator,
             .topicAlias,
             .subscriptionIdentifier: .publish
        case .maximumQoS: .connAck
        default: .connect
        }
        #expect(PropertyRules.validate([property], in: context) == .failure(.invalidValue(identifier: property.identifier)))
    }

    @Test func decoderRejectsAPropertyNotAllowedInThePacket() {
        // DISCONNECT, reason 0x00, properties: Topic Alias (0x23) = 1 — not allowed in DISCONNECT.
        #expect(
            Packet.decode([0xE0, 0x05, 0x00, 0x03, 0x23, 0x00, 0x01], for: .v5)
                == .failure(.invalidProperty(.notAllowed(identifier: 0x23, in: .disconnect)))
        )
    }

    @Test func encoderRefusesInvalidProperties() {
        let packet = Packet.disconnect(Disconnect(reasonCode: .serverShuttingDown, properties: [.reasonString("a"), .reasonString("b")]))
        #expect(packet.encode(for: .v5) == .failure(.invalidProperty(.duplicate(identifier: 0x1F))))
    }
}
