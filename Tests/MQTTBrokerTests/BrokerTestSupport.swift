// SPDX-License-Identifier: Apache-2.0

import Foundation
import FP
import MQTT
import MQTTBroker

// swiftlint:disable force_unwrapping
func topic(_ value: String) -> TopicName { TopicName(rawValue: value)! }
func filter(_ value: String) -> TopicFilter { TopicFilter(rawValue: value)! }
func id(_ value: UInt16) -> PacketIdentifier { PacketIdentifier(rawValue: value)! }
// swiftlint:enable force_unwrapping

let alice = ConnectionID.accepted(1)
let bob = ConnectionID.accepted(2)
let carol = ConnectionID.accepted(3)

func wire(_ packet: Packet, _ version: ProtocolVersion = .v5) -> [UInt8] {
    (try? packet.encode(for: version).get()) ?? []
}

func connect(
    _ client: String,
    version: ProtocolVersion = .v5,
    cleanStart: Bool = true,
    keepAlive: UInt16 = 0,
    will: Will? = nil,
    properties: [Property] = []
) -> Packet {
    .connect(Connect(
        protocolVersion: version,
        clientIdentifier: client,
        cleanStart: cleanStart,
        keepAlive: keepAlive,
        will: will,
        userName: nil,
        password: nil,
        properties: properties
    ))
}

func from(_ connection: ConnectionID, _ packet: Packet, _ version: ProtocolVersion = .v5) -> BrokerInput {
    .connection(.received(connection, wire(packet, version)))
}

func open(_ connection: ConnectionID) -> BrokerInput {
    .connection(.accepted(connection))
}

func tick(_ seconds: Int) -> BrokerInput {
    .connection(.tick(.seconds(seconds)))
}

/// Accepts a connection and completes its CONNECT.
func join(_ connection: ConnectionID, _ client: String, _ packet: Packet? = nil) -> [BrokerInput] {
    [open(connection), from(connection, packet ?? connect(client))]
}

func subscription(_ value: String, _ qos: QoS = .atLeastOnce) -> Subscription {
    Subscription(filter: filter(value), options: .qos(qos))
}

func subscribe(_ subscriptions: [Subscription], identifier: UInt16 = 1, properties: [Property] = []) -> Packet {
    .subscribe(Subscribe(packetIdentifier: id(identifier), subscriptions: subscriptions, properties: properties))
}

func publish(_ name: String, _ payload: String = "x", qos: QoS = .atMostOnce, identifier: UInt16 = 1, retain: Bool = false) -> Packet {
    .publish(Publish(
        topic: topic(name),
        payload: Array(payload.utf8),
        delivery: .make(qos, identifier: id(identifier)),
        retain: retain,
        duplicate: false,
        properties: []
    ))
}

/// Runs inputs through a broker, returning every command and the final state.
func run(
    _ inputs: [BrokerInput],
    from state: BrokerState = .initial(BrokerOptions()),
    policy: BrokerPolicy = .open
) -> ([BrokerCommand], BrokerState) {
    let step = BrokerMachine.step(policy)
    return inputs.reduce(([BrokerCommand](), state)) { acc, input in
        let (commands, next) = step(input).runStateful(acc.1)
        return (acc.0 + commands, next)
    }
}

/// The packets sent to one connection.
func sent(_ commands: [BrokerCommand], to connection: ConnectionID) -> [Packet] {
    commands.compactMap { command in
        guard case let .send(target, packet, _) = command, target == connection else { return nil }
        return packet
    }
}

func publishes(_ commands: [BrokerCommand], to connection: ConnectionID) -> [Publish] {
    sent(commands, to: connection).compactMap { packet in
        guard case let .publish(publish) = packet else { return nil }
        return publish
    }
}

func closes(_ commands: [BrokerCommand]) -> [ConnectionID] {
    commands.compactMap { command in
        guard case let .close(target) = command else { return nil }
        return target
    }
}

func payloads(_ publishes: [Publish]) -> [String] {
    publishes.map { String(bytes: $0.payload, encoding: .utf8) ?? "" }
}
