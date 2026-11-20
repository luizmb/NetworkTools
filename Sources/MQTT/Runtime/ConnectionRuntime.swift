// SPDX-License-Identifier: Apache-2.0

import FP
import ReactiveConcurrency

/// Identifies one byte connection inside a runtime: connections a machine opens are `outgoing`,
/// connections a listener accepts are `accepted`. Numbers are never reused within a run, so input
/// from a connection that was already replaced is recognisable as stale.
public enum ConnectionID: Sendable, Hashable, Comparable, CustomStringConvertible {
    /// A connection opened by the machine (``RuntimeCommand/open(_:)``).
    case outgoing(UInt64)
    /// A connection accepted from the runtime's `Listener`.
    case accepted(UInt64)

    /// `out#n` / `in#n`.
    public var description: String {
        switch self {
        case let .outgoing(number): "out#\(number)"
        case let .accepted(number): "in#\(number)"
        }
    }
}

/// What the runtime tells a machine about its connections and about time.
public enum ConnectionInput: Sendable, Hashable {
    /// An outgoing connection is open.
    case opened(ConnectionID)
    /// An outgoing connection could not be opened.
    case openFailed(ConnectionID, TransportError)
    /// A listener accepted a connection.
    case accepted(ConnectionID)
    /// Bytes arrived on a connection.
    case received(ConnectionID, [UInt8])
    /// The peer closed a connection.
    case closed(ConnectionID)
    /// A connection broke (or a write to it failed).
    case failed(ConnectionID, TransportError)
    /// The clock ticked: the current monotonic time, as elapsed time since an arbitrary origin.
    case tick(Duration)
    /// The listener failed and accepts no more connections.
    case listenerFailed(TransportError)
}

/// What a machine asks the runtime to do.
public enum RuntimeCommand<Event: Sendable, Failure: Error>: Sendable {
    /// Open a new outgoing connection with this identifier.
    case open(ConnectionID)
    /// Open a new outgoing connection to the server an MQTT 5 Server Reference names, through the
    /// world's `RuntimeWorld/redirect` (the connection fails when the world has no transport for it).
    case redirect(ConnectionID, to: String)
    /// Encode `packet` for `version` and write it to a connection.
    case send(ConnectionID, Packet, ProtocolVersion)
    /// Close a connection.
    case close(ConnectionID)
    /// Emit an event downstream.
    case emit(Event)
    /// End the run with a failure (every connection is closed first).
    case fail(Failure)
    /// End the run normally (every connection is closed first).
    case finish
}

extension RuntimeCommand: Equatable where Event: Equatable, Failure: Equatable {}
extension RuntimeCommand: Hashable where Event: Hashable, Failure: Hashable {}

/// Runs a pure connection machine: the one effect interpreter shared by the MQTT client, broker
/// and bridge.
///
/// The machine is `step: (Input) -> Stateful<State, [RuntimeCommand]>`. The runtime merges its
/// inputs — the caller's `external` publisher, clock ticks, accepted connections, received bytes,
/// open/close/failure notifications — folds them through `step`, and performs the commands in
/// order. Open connections are part of the fold's accumulator, never global state, and every
/// subscription starts a fresh run. Cancelling the run cancels every connection's `receive`,
/// which closes it.
public enum ConnectionRuntime {
    /// Builds a run.
    /// - Parameters:
    ///   - initial: The machine's initial state.
    ///   - step: The machine.
    ///   - lift: Wraps a connection/clock input into the machine's input type.
    ///   - external: The machine's other inputs (application requests, …).
    ///   - encodingFailure: Wraps a packet that could not be encoded into the run's failure.
    /// - Returns: The run, waiting for its world.
    public static func run<State: Sendable, Input: Sendable, Event: Sendable, Failure: Error>(
        initial: State,
        step: @escaping @Sendable (Input) -> Stateful<State, [RuntimeCommand<Event, Failure>]>,
        lift: @escaping @Sendable (ConnectionInput) -> Input,
        external: Publisher<Input, Never>,
        encodingFailure: @escaping @Sendable (MQTTEncodingError) -> Failure
    ) -> Reader<RuntimeWorld, Publisher<Event, Failure>> {
        Reader { world in
            // `just(()).flatMap` defers construction: every subscription gets its own feedback streams.
            Publisher<Void, Failure>.just(()).flatMap(maxPublishers: 1) { _ in
                Run(world: world, step: step, lift: lift, encodingFailure: encodingFailure)
                    .events(initial: initial, external: external)
            }
        }
    }
}

/// One run's wiring. A value: the feedback streams are created per subscription by
/// ``ConnectionRuntime/run(initial:step:lift:external:encodingFailure:)``.
private struct Run<State: Sendable, Input: Sendable, Event: Sendable, Failure: Error>: Sendable {
    typealias Command = RuntimeCommand<Event, Failure>

    enum Signal: Sendable {
        case input(Input)
        case attach(ConnectionID, TransportConnection, announce: ConnectionInput)
    }

    enum Action: Sendable {
        case command(Command)
        case receive(ConnectionID, TransportConnection)
    }

    struct Fold: Sendable {
        var state: State
        var connections: [ConnectionID: TransportConnection]
        var actions: [Action]
    }

    enum Performed: Sendable {
        case event(Event)
        case finished
    }

    let world: RuntimeWorld
    let step: @Sendable (Input) -> Stateful<State, [Command]>
    let lift: @Sendable (ConnectionInput) -> Input
    let encodingFailure: @Sendable (MQTTEncodingError) -> Failure
    let feedback: AsyncStream<Signal>.Continuation
    let feedbackStream: AsyncStream<Signal>
    let links: AsyncStream<(ConnectionID, TransportConnection)>.Continuation
    let linkStream: AsyncStream<(ConnectionID, TransportConnection)>

    init(
        world: RuntimeWorld,
        step: @escaping @Sendable (Input) -> Stateful<State, [Command]>,
        lift: @escaping @Sendable (ConnectionInput) -> Input,
        encodingFailure: @escaping @Sendable (MQTTEncodingError) -> Failure
    ) {
        self.world = world
        self.step = step
        self.lift = lift
        self.encodingFailure = encodingFailure
        (feedbackStream, feedback) = AsyncStream<Signal>.makeStream()
        (linkStream, links) = AsyncStream<(ConnectionID, TransportConnection)>.makeStream()
    }

    func events(initial: State, external: Publisher<Input, Never>) -> Publisher<Event, Failure> {
        signals(external: external)
            .scan(Fold(state: initial, connections: [:], actions: []), fold)
            .setFailureType(to: Failure.self)
            .flatMap(maxPublishers: 1, perform)
            .prefix { $0.isEvent }
            .compactMap(\.event)
    }

    private func signals(external: Publisher<Input, Never>) -> Publisher<Signal, Never> {
        let lift = lift
        let accepted = world.listener.accept()
            .scan((number: UInt64(0), connection: TransportConnection?.none)) { acc, connection in
                (number: acc.number + 1, connection: connection)
            }
            .compactMap { numbered in
                numbered.connection.map { Signal.attach(.accepted(numbered.number), $0, announce: .accepted(.accepted(numbered.number))) }
            }
            .tryCatch { Publisher<Signal, Never>.just(.input(lift(.listenerFailed($0)))) }
        let received = DeferredStream { linkStream }.eraseToPublisher()
            .flatMap { id, connection in
                connection.receive
                    .map { Signal.input(lift(.received(id, $0))) }
                    .append(Signal.input(lift(.closed(id))))
                    .tryCatch { Publisher<Signal, Never>.just(.input(lift(.failed(id, $0)))) }
            }
        return Publisher<Signal, Never>.merge([
            external.map(Signal.input),
            world.clock().map { Signal.input(lift(.tick($0))) },
            DeferredStream { feedbackStream }.eraseToPublisher(),
            accepted,
            received,
        ])
    }

    @Sendable private func fold(_ fold: Fold, _ signal: Signal) -> Fold {
        switch signal {
        case let .input(input):
            let (commands, state) = step(input).runStateful(fold.state)
            return Fold(state: state, connections: fold.connections, actions: commands.map(Action.command))
        case let .attach(id, connection, announce):
            let (commands, state) = step(lift(announce)).runStateful(fold.state)
            var connections = fold.connections
            connections[id] = connection
            return Fold(state: state, connections: connections, actions: [.receive(id, connection)] + commands.map(Action.command))
        }
    }

    @Sendable private func perform(_ fold: Fold) -> Publisher<Performed, Failure> {
        fold.actions
            .map { action($0, connections: fold.connections) }
            .reduce(Publisher<Performed, Failure>.empty()) { $0.append($1) }
    }

    private func action(_ action: Action, connections: [ConnectionID: TransportConnection]) -> Publisher<Performed, Failure> {
        switch action {
        case let .command(command):
            effect(command, connections: connections)
        case let .receive(id, connection):
            Publisher<Performed, Failure>.empty().handleEvents(receiveSubscription: { [links] in links.yield((id, connection)) })
        }
    }

    private func effect(_ command: Command, connections: [ConnectionID: TransportConnection]) -> Publisher<Performed, Failure> {
        switch command {
        case let .open(id):
            open(id, through: world.transport)
        case let .redirect(id, reference):
            world.redirect(reference).map { open(id, through: $0) }
                ?? open(id, through: Transport { .fail(.connectionFailed("no transport for server reference \(reference)")) })
        case let .send(id, packet, version):
            send(packet, version: version, on: id, connections: connections)
        case let .close(id):
            connections[id].map { $0.close().setFailureType(to: Failure.self).flatMap(const(.empty())) } ?? .empty()
        case let .emit(event):
            .just(.event(event))
        case let .fail(error):
            closeAll(connections).flatMap(const(Publisher<Performed, Failure>.fail(error)))
        case .finish:
            closeAll(connections).map(const(.finished))
        }
    }

    private func open(_ id: ConnectionID, through transport: Transport) -> Publisher<Performed, Failure> {
        let feedback = feedback
        let lift = lift
        return transport.connect()
            .map { Signal.attach(id, $0, announce: .opened(id)) }
            .tryCatch { Publisher<Signal, Never>.just(.input(lift(.openFailed(id, $0)))) }
            .map { signal in
                feedback.yield(signal)
                return ()
            }
            .setFailureType(to: Failure.self)
            .flatMap(const(Publisher<Performed, Failure>.empty()))
    }

    private func send(
        _ packet: Packet,
        version: ProtocolVersion,
        on id: ConnectionID,
        connections: [ConnectionID: TransportConnection]
    ) -> Publisher<Performed, Failure> {
        let feedback = feedback
        let lift = lift
        return switch (packet.encode(for: version), connections[id]) {
        case let (.success(bytes), .some(connection)):
            connection.send(bytes)
                .map(const(Signal?.none))
                .tryCatch { Publisher<Signal?, Never>.just(.input(lift(.failed(id, $0)))) }
                .map { signal in
                    if let signal { feedback.yield(signal) }
                }
                .setFailureType(to: Failure.self)
                .flatMap(const(Publisher<Performed, Failure>.empty()))
        case (.success, .none):
            .empty()
        case let (.failure(error), _):
            .fail(encodingFailure(error))
        }
    }

    private func closeAll(_ connections: [ConnectionID: TransportConnection]) -> Publisher<Void, Failure> {
        connections.values
            .map { $0.close() }
            .reduce(Publisher<Void, Never>.just(())) { $0.append($1) }
            .collect()
            .map(ignore)
            .setFailureType(to: Failure.self)
    }
}

private extension Run.Performed {
    var isEvent: Bool {
        if case .event = self { true } else { false }
    }

    var event: Event? {
        if case let .event(event) = self { event } else { nil }
    }
}
