// SPDX-License-Identifier: Apache-2.0

import FP
import MQTT
import MQTTClient

// swiftlint:disable force_unwrapping
func topic(_ value: String) -> TopicName { TopicName(rawValue: value)! }
func filter(_ value: String) -> TopicFilter { TopicFilter(rawValue: value)! }
func id(_ value: UInt16) -> PacketIdentifier { PacketIdentifier(rawValue: value)! }
// swiftlint:enable force_unwrapping

let c1 = ConnectionID.outgoing(1)
let c2 = ConnectionID.outgoing(2)
let accepted = ConnAck(sessionPresent: false, reasonCode: .success, properties: [])
let backoff = ReconnectPolicy.exponentialBackoff(initial: .seconds(1), maximum: .seconds(8), attempts: 3)

func options(
    _ version: ProtocolVersion = .v5,
    keepAlive: UInt16 = 30,
    cleanStart: Bool = true,
    properties: [Property] = [],
    reconnect: ReconnectPolicy = .never
) -> ClientOptions {
    ClientOptions(
        version: version,
        clientIdentifier: "test",
        cleanStart: cleanStart,
        keepAlive: keepAlive,
        will: nil,
        userName: "elegoo",
        password: Array("code".utf8),
        properties: properties,
        maximumPacketSize: 1 << 16,
        connectTimeout: .seconds(10),
        reconnect: reconnect
    )
}

func wire(_ packet: Packet, _ version: ProtocolVersion = .v5) -> [UInt8] {
    (try? packet.encode(for: version).get()) ?? []
}

/// Inputs from the server on a connection.
func rx(_ packet: Packet, on connection: ConnectionID = c1, _ version: ProtocolVersion = .v5) -> ClientInput {
    .connection(.received(connection, wire(packet, version)))
}

func tick(_ seconds: Int) -> ClientInput {
    .connection(.tick(.seconds(seconds)))
}

func request(_ request: ClientRequest) -> ClientInput {
    .request(request)
}

/// The CONNECT these options produce (MQTT 5 announces the Maximum Packet Size).
func expectedConnect(_ options: ClientOptions) -> Packet {
    .connect(Connect(
        protocolVersion: options.version,
        clientIdentifier: options.clientIdentifier,
        cleanStart: options.cleanStart,
        keepAlive: options.keepAlive,
        will: nil,
        userName: options.userName,
        password: options.password,
        properties: options.version == .v5 ? options.properties + [.maximumPacketSize(1 << 16)] : options.properties
    ))
}

/// Runs inputs through the machine, returning every command and the final state.
func run(_ inputs: [ClientInput], from state: ClientState) -> ([ClientCommand], ClientState) {
    inputs.reduce(([ClientCommand](), state)) { acc, input in
        let (commands, next) = ClientMachine.step(input).runStateful(acc.1)
        return (acc.0 + commands, next)
    }
}

/// A client that has completed the handshake on `c1` at time zero.
func connected(_ options: ClientOptions = options(), ack: ConnAck = accepted) -> ClientState {
    run([.start, .connection(.opened(c1)), rx(.connAck(ack), options.version)], from: .initial(options)).1
}

func message(_ qos: QoS, topic name: String = "a/b") -> OutgoingMessage {
    OutgoingMessage(topic: topic(name), payload: [1], qos: qos, retain: false, properties: [])
}

func sent(_ commands: [ClientCommand]) -> [Packet] {
    commands.compactMap { command in
        guard case let .send(_, packet, _) = command else { return nil }
        return packet
    }
}

func publishes(_ commands: [ClientCommand]) -> [Publish] {
    sent(commands).compactMap { packet in
        guard case let .publish(publish) = packet else { return nil }
        return publish
    }
}

func events(_ commands: [ClientCommand]) -> [ClientEvent] {
    commands.compactMap { command in
        guard case let .emit(event) = command else { return nil }
        return event
    }
}
