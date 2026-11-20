// SPDX-License-Identifier: Apache-2.0

import FP
import MQTT
import ReactiveConcurrency

/// The effects a client needs from the outside world, injected through `Reader`.
public struct ClientWorld: Sendable {
    /// Opens byte connections to the broker (one per connect/reconnect).
    public let transport: Transport
    /// A periodic monotonic clock driving keep-alive, timeouts and reconnect backoff, e.g.
    /// `.monotonicTicks(every: .milliseconds(250), clock: ContinuousClock())`. Tests pass a
    /// hand-driven publisher.
    public let clock: @Sendable () -> Publisher<Duration, Never>
    /// The transport to the server an MQTT 5 Server Reference names, when the server redirects the
    /// client ("Use another server" / "Server moved"); `nil` to not follow it.
    public let redirect: @Sendable (_ serverReference: String) -> Transport?

    /// Creates a world.
    /// - Parameters:
    ///   - transport: Opens connections.
    ///   - clock: A periodic monotonic clock.
    ///   - redirect: Transports for server references; by default redirects are not followed.
    public init(
        transport: Transport,
        clock: @escaping @Sendable () -> Publisher<Duration, Never>,
        redirect: @escaping @Sendable (_ serverReference: String) -> Transport? = { _ in nil }
    ) {
        self.transport = transport
        self.clock = clock
        self.redirect = redirect
    }

    var runtime: RuntimeWorld {
        RuntimeWorld(transport: transport, listener: .none, clock: clock, redirect: redirect)
    }
}

/// An MQTT client session as a stream transducer.
///
/// ```swift
/// let world = ClientWorld(
///     transport: .nwConnection(host: "192.168.1.20", port: 1883, parameters: .tcp, queue: queue),
///     clock: { .monotonicTicks(every: .milliseconds(250), clock: ContinuousClock()) }
/// )
/// let events: Publisher<ClientEvent, ClientError> =
///     MQTTClient.session(options, requests: requests).runReader(world)
/// ```
///
/// The application supplies its requests as a publisher and gets the session's events back.
/// Nothing happens until the returned publisher is subscribed; subscribing connects, and
/// cancelling closes the connection. With a ``ReconnectPolicy`` the session survives lost
/// connections (resuming the MQTT session or re-subscribing) and reports them as
/// ``ClientEvent/connectionLost(_:retryingIn:)``. It finishes after a DISCONNECT that is not
/// retried and fails with a typed ``ClientError`` otherwise.
///
/// The protocol is ``ClientMachine/step(_:)``; this function only plugs it into the shared
/// `ConnectionRuntime`.
public enum MQTTClient {
    /// Builds a client session.
    /// - Parameters:
    ///   - options: How to connect.
    ///   - requests: What the application wants done, in order. Subscribed once for the whole
    ///     session, across reconnects; requests made while disconnected are queued.
    /// - Returns: The session, waiting for its world.
    public static func session(
        _ options: ClientOptions,
        requests: Publisher<ClientRequest, Never>
    ) -> Reader<ClientWorld, Publisher<ClientEvent, ClientError>> {
        ConnectionRuntime.run(
            initial: ClientState.initial(options),
            step: ClientMachine.step,
            lift: ClientInput.connection,
            external: Publisher<ClientInput, Never>.just(.start).append(requests.map(ClientInput.request)),
            encodingFailure: ClientError.encoding
        )
        .contramapEnvironment(get(\ClientWorld.runtime))
    }
}
