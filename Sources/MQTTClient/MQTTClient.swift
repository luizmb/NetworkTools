// SPDX-License-Identifier: Apache-2.0

import FP
import MQTT
import ReactiveConcurrency

/// The effects a client session needs from the outside world, injected through `Reader`.
public struct ClientWorld: Sendable {
    /// Opens the byte connection to the broker.
    public let transport: Transport
    /// Emits once every `seconds` seconds, forever. Production code passes a clock-driven timer
    /// (e.g. ReactiveConcurrency's `Publisher.timer(every:clock:)`); tests pass a manual one.
    public let keepAliveTimer: @Sendable (_ seconds: UInt16) -> Publisher<Void, Never>

    /// Creates a world.
    /// - Parameters:
    ///   - transport: Opens the byte connection.
    ///   - keepAliveTimer: A periodic tick source.
    public init(transport: Transport, keepAliveTimer: @escaping @Sendable (_ seconds: UInt16) -> Publisher<Void, Never>) {
        self.transport = transport
        self.keepAliveTimer = keepAliveTimer
    }
}

/// An MQTT client session as a stream transducer.
///
/// ```swift
/// let session: Publisher<ClientEvent, ClientError> =
///     MQTTClient.session(options, requests: requests).runReader(world)
/// ```
///
/// The application supplies its requests as a publisher (fed by its store, a subject, …) and
/// gets the session's events back. Nothing happens until the returned publisher is subscribed;
/// subscribing opens the connection and starts the session, cancelling closes it. The session
/// finishes after a requested or server-sent DISCONNECT and fails with a typed
/// ``ClientError`` otherwise.
///
/// Internally the inputs (connection opened, bytes received, requests, keep-alive ticks) are
/// folded with ``ClientMachine/step(_:)`` — the whole protocol is that pure function — and the
/// outputs it describes are performed in order: packets are encoded and sent, events emitted,
/// the connection closed.
public enum MQTTClient {
    /// Builds a client session.
    /// - Parameters:
    ///   - options: How to connect.
    ///   - requests: What the application wants done, in order.
    /// - Returns: The session, waiting for its world.
    public static func session(
        _ options: ClientOptions,
        requests: Publisher<ClientRequest, Never>
    ) -> Reader<ClientWorld, Publisher<ClientEvent, ClientError>> {
        Reader { world in
            world.transport.connect()
                .mapError(ClientError.transport)
                .flatMap(maxPublishers: 1) { connection in
                    run(options, requests: requests, ticks: ticks(options.keepAlive, world), connection: connection)
                }
        }
    }

    static func run(
        _ options: ClientOptions,
        requests: Publisher<ClientRequest, Never>,
        ticks: Publisher<ClientInput, Never>,
        connection: TransportConnection
    ) -> Publisher<ClientEvent, ClientError> {
        inputs(requests: requests, ticks: ticks, connection: connection)
            .scan(Fold(state: .initial(options), outputs: [])) { fold, input in
                let (outputs, state) = ClientMachine.step(input).runStateful(fold.state)
                return Fold(state: state, outputs: outputs)
            }
            .setFailureType(to: ClientError.self)
            .flatMap(maxPublishers: 1) { perform($0.outputs, version: options.version, connection: connection) }
            .prefix { $0 != .finished }
            .compactMap(\.event)
    }

    /// The session's inputs: `start` first, then bytes, requests and ticks as they come.
    static func inputs(
        requests: Publisher<ClientRequest, Never>,
        ticks: Publisher<ClientInput, Never>,
        connection: TransportConnection
    ) -> Publisher<ClientInput, Never> {
        let received = connection.receive
            .map(ClientInput.received)
            .append(.transportClosed)
            .tryCatch { error in Publisher<ClientInput, Never>.just(.transportFailed(error)) }
        return Publisher<ClientInput, Never>.just(.start)
            .append(.merge([received, requests.map(ClientInput.request), ticks]))
    }

    static func ticks(_ keepAlive: UInt16, _ world: ClientWorld) -> Publisher<ClientInput, Never> {
        keepAlive == 0 ? .empty() : world.keepAliveTimer(keepAlive).map(const(ClientInput.keepAliveTick))
    }

    /// Performs the outputs of one step, strictly in order.
    static func perform(
        _ outputs: [ClientOutput],
        version: ProtocolVersion,
        connection: TransportConnection
    ) -> Publisher<Performed, ClientError> {
        outputs
            .map { effect($0, version: version, connection: connection) }
            .reduce(Publisher<Performed, ClientError>.empty()) { $0.append($1) }
    }

    static func effect(
        _ output: ClientOutput,
        version: ProtocolVersion,
        connection: TransportConnection
    ) -> Publisher<Performed, ClientError> {
        switch output {
        case let .send(packet):
            packet.encode(for: version).publisher
                .mapError(ClientError.encoding)
                .flatMap { connection.send($0).mapError(ClientError.transport) }
                .flatMap(const(Publisher<Performed, ClientError>.empty()))
        case let .event(event):
            .just(.event(event))
        case .close:
            connection.close().setFailureType(to: ClientError.self).map(const(Performed.finished))
        case let .fail(error):
            connection.close().setFailureType(to: ClientError.self).flatMap(const(Publisher<Performed, ClientError>.fail(error)))
        }
    }

    struct Fold: Sendable {
        let state: ClientState
        let outputs: [ClientOutput]
    }

    enum Performed: Sendable, Hashable {
        case event(ClientEvent)
        case finished

        var event: ClientEvent? {
            switch self {
            case let .event(event): event
            case .finished: nil
            }
        }
    }
}
