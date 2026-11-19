// SPDX-License-Identifier: Apache-2.0

import FP
import MQTT

/// Something that happens to a client session.
public enum ClientInput: Sendable, Hashable {
    /// The transport is open: send CONNECT.
    case start
    /// Bytes arrived from the server.
    case received([UInt8])
    /// The application asked for something.
    case request(ClientRequest)
    /// A keep-alive interval elapsed.
    case keepAliveTick
    /// The transport's inbound side finished.
    case transportClosed
    /// The transport broke.
    case transportFailed(TransportError)
}

/// Something the session wants done. The machine only describes effects; the interpreter in
/// ``MQTTClient`` performs them in order.
public enum ClientOutput: Sendable, Hashable {
    /// Encode and send a packet.
    case send(Packet)
    /// Tell the application something.
    case event(ClientEvent)
    /// End the session with a failure (the transport is closed first).
    case fail(ClientError)
    /// End the session normally (the transport is closed).
    case close
}

/// The client protocol as a pure state machine.
///
/// ``step(_:)`` folds one ``ClientInput`` into the ``ClientState`` and returns the outputs it
/// causes. It never touches a socket, a clock or a random number generator, so every
/// behaviour — handshake, keep-alive, QoS 1 and 2 in both directions, packet identifiers,
/// protocol violations — is tested by feeding inputs and comparing outputs.
public enum ClientMachine {
    /// One transition of the client protocol.
    /// - Parameter input: What happened.
    /// - Returns: A state step producing the outputs, in order.
    public static func step(_ input: ClientInput) -> Stateful<ClientState, [ClientOutput]> {
        Stateful { state in
            state.phase == .closed ? [] : transition(input, &state)
        }
    }

    private static func transition(_ input: ClientInput, _ state: inout ClientState) -> [ClientOutput] {
        switch input {
        case .start:
            start(&state)
        case let .received(bytes):
            receive(bytes, &state)
        case let .request(request):
            perform(request, &state)
        case .keepAliveTick:
            keepAlive(&state)
        case .transportClosed:
            end(&state, [.fail(.connectionClosed)])
        case let .transportFailed(error):
            end(&state, [.fail(.transport(error))])
        }
    }

    // MARK: - Lifecycle

    private static func start(_ state: inout ClientState) -> [ClientOutput] {
        guard state.phase == .idle else { return [] }
        state.phase = .connecting
        return [.send(.connect(state.options.connect))]
    }

    private static func keepAlive(_ state: inout ClientState) -> [ClientOutput] {
        switch (state.phase, state.pingOutstanding) {
        case (.connecting, true),
             (.connected, true):
            return end(&state, [.fail(.keepAliveTimeout)])
        case (.connecting, false):
            state.pingOutstanding = true
            return []
        case (.connected, false):
            state.pingOutstanding = true
            return [.send(.pingReq)]
        case (.idle, _),
             (.closed, _):
            return []
        }
    }

    private static func end(_ state: inout ClientState, _ outputs: [ClientOutput]) -> [ClientOutput] {
        state.phase = .closed
        return outputs
    }

    /// Ends the session because of the server, telling it why first when MQTT 5 allows it.
    private static func abort(_ state: inout ClientState, _ reason: ReasonCode, _ error: ClientError) -> [ClientOutput] {
        let notice: [ClientOutput] = state.options.version == .v5
            ? [.send(.disconnect(Disconnect(reasonCode: reason, properties: [])))]
            : []
        return end(&state, notice + [.fail(error)])
    }

    // MARK: - Application requests

    private static func perform(_ request: ClientRequest, _ state: inout ClientState) -> [ClientOutput] {
        guard state.phase == .connected else {
            state.queued.append(request)
            return []
        }
        switch request {
        case let .publish(message):
            return publish(message, &state)
        case let .subscribe(subscriptions, properties):
            return withIdentifier(&state) { identifier, state in
                state.inFlight[identifier] = .subscribing(subscriptions)
                return [.send(.subscribe(Subscribe(packetIdentifier: identifier, subscriptions: subscriptions, properties: properties)))]
            }
        case let .unsubscribe(filters, properties):
            return withIdentifier(&state) { identifier, state in
                state.inFlight[identifier] = .unsubscribing(filters)
                return [.send(.unsubscribe(Unsubscribe(packetIdentifier: identifier, filters: filters, properties: properties)))]
            }
        case let .authenticate(auth):
            return [.send(.auth(auth))]
        case let .disconnect(disconnect):
            return end(&state, [.send(.disconnect(disconnect)), .event(.disconnected(disconnect, byServer: false)), .close])
        }
    }

    private static func publish(_ message: OutgoingMessage, _ state: inout ClientState) -> [ClientOutput] {
        let make = { (delivery: Delivery) in
            Publish(
                topic: message.topic,
                payload: message.payload,
                delivery: delivery,
                retain: message.retain,
                duplicate: false,
                properties: message.properties
            )
        }
        guard message.qos != .atMostOnce else { return [.send(.publish(make(.atMostOnce)))] }
        return withIdentifier(&state) { identifier, state in
            let publish = make(.make(message.qos, identifier: identifier))
            state.inFlight[identifier] = message.qos == .atLeastOnce ? .awaitingPubAck(publish) : .awaitingPubRec(publish)
            return [.send(.publish(publish))]
        }
    }

    /// Reserves the next free packet identifier and runs `body` with it.
    private static func withIdentifier(
        _ state: inout ClientState,
        _ body: (PacketIdentifier, inout ClientState) -> [ClientOutput]
    ) -> [ClientOutput] {
        let candidates = Swift.sequence(first: state.nextIdentifier, next: \.next).prefix(Int(UInt16.max))
        guard let identifier = candidates.first(where: { state.inFlight[$0] == nil }) else {
            return end(&state, [.fail(.packetIdentifiersExhausted)])
        }
        state.nextIdentifier = identifier.next
        return body(identifier, &state)
    }

    // MARK: - Server packets

    private static func receive(_ bytes: [UInt8], _ state: inout ClientState) -> [ClientOutput] {
        let (decoded, stream) = PacketStream.feed(bytes).runStateful(state.stream)
        state.stream = stream
        switch decoded {
        case let .success(packets):
            return packets.reduce(into: [ClientOutput]()) { outputs, packet in
                outputs += state.phase == .closed ? [] : handle(packet, &state)
            }
        case let .failure(error):
            return abort(&state, .malformedPacket, .decoding(error))
        }
    }

    private static func handle(_ packet: Packet, _ state: inout ClientState) -> [ClientOutput] {
        switch (state.phase, packet) {
        case let (.connecting, .connAck(ack)):
            return connected(ack, &state)
        case let (.connecting, .auth(auth)),
             let (.connected, .auth(auth)):
            return [.event(.authenticationChallenge(auth))]
        case let (.connecting, .disconnect(disconnect)),
             let (.connected, .disconnect(disconnect)):
            return end(&state, [.event(.disconnected(disconnect, byServer: true)), .close])
        case let (.connected, .publish(publish)):
            return incoming(publish, &state)
        case let (.connected, .pubAck(ack)):
            return acknowledge(ack, .pubAck, &state)
        case let (.connected, .pubRec(ack)):
            return acknowledge(ack, .pubRec, &state)
        case let (.connected, .pubRel(ack)):
            return release(ack, &state)
        case let (.connected, .pubComp(ack)):
            return acknowledge(ack, .pubComp, &state)
        case let (.connected, .subAck(ack)):
            return acknowledge(ack, &state)
        case let (.connected, .unsubAck(ack)):
            return acknowledge(ack, &state)
        case (.connected, .pingResp):
            state.pingOutstanding = false
            return []
        default:
            return abort(&state, .protocolError, .protocolViolation(.unexpectedPacket(packet.type)))
        }
    }

    private static func connected(_ ack: ConnAck, _ state: inout ClientState) -> [ClientOutput] {
        guard !ack.reasonCode.isFailure else {
            return end(&state, [.fail(.connectionRefused(ack))])
        }
        state.phase = .connected
        state.pingOutstanding = false
        let queued = state.queued
        state.queued = []
        return queued.reduce(into: [.event(.connected(ack))]) { outputs, request in
            outputs += state.phase == .closed ? [] : perform(request, &state)
        }
    }

    private static func incoming(_ publish: Publish, _ state: inout ClientState) -> [ClientOutput] {
        switch publish.delivery {
        case .atMostOnce:
            return [.event(.message(publish))]
        case let .atLeastOnce(identifier):
            return [.event(.message(publish)), .send(.pubAck(.success(identifier)))]
        case let .exactlyOnce(identifier):
            let isNew = state.receivedQoS2.insert(identifier).inserted
            return (isNew ? [.event(.message(publish))] : []) + [.send(.pubRec(.success(identifier)))]
        }
    }

    private static func release(_ ack: Acknowledgement, _ state: inout ClientState) -> [ClientOutput] {
        let known = state.receivedQoS2.remove(ack.packetIdentifier) != nil
        let reason: ReasonCode = known || state.options.version == .v3_1_1 ? .success : .packetIdentifierNotFound
        return [.send(.pubComp(Acknowledgement(packetIdentifier: ack.packetIdentifier, reasonCode: reason, properties: [])))]
    }

    private static func acknowledge(_ ack: Acknowledgement, _ type: PacketType, _ state: inout ClientState) -> [ClientOutput] {
        let identifier = ack.packetIdentifier
        switch (type, state.inFlight[identifier]) {
        case let (.pubAck, .awaitingPubAck(publish)),
             let (.pubComp, .awaitingPubComp(publish)):
            state.inFlight[identifier] = nil
            return [.event(.published(publish, ack))]
        case let (.pubRec, .awaitingPubRec(publish)) where ack.reasonCode.isFailure:
            state.inFlight[identifier] = nil
            return [.event(.published(publish, ack))]
        case let (.pubRec, .awaitingPubRec(publish)),
             let (.pubRec, .awaitingPubComp(publish)):
            state.inFlight[identifier] = .awaitingPubComp(publish)
            return [.send(.pubRel(.success(identifier)))]
        default:
            return abort(&state, .protocolError, .protocolViolation(.unknownPacketIdentifier(type, identifier)))
        }
    }

    private static func acknowledge(_ ack: SubAck, _ state: inout ClientState) -> [ClientOutput] {
        guard case let .subscribing(subscriptions) = state.inFlight[ack.packetIdentifier] else {
            return abort(&state, .protocolError, .protocolViolation(.unknownPacketIdentifier(.subAck, ack.packetIdentifier)))
        }
        state.inFlight[ack.packetIdentifier] = nil
        return [.event(.subscribed(subscriptions, ack))]
    }

    private static func acknowledge(_ ack: UnsubAck, _ state: inout ClientState) -> [ClientOutput] {
        guard case let .unsubscribing(filters) = state.inFlight[ack.packetIdentifier] else {
            return abort(&state, .protocolError, .protocolViolation(.unknownPacketIdentifier(.unsubAck, ack.packetIdentifier)))
        }
        state.inFlight[ack.packetIdentifier] = nil
        return [.event(.unsubscribed(filters, ack))]
    }
}
