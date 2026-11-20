// SPDX-License-Identifier: Apache-2.0

import FP
import MQTT
import ReactiveConcurrency

/// The effects a broker needs from the outside world, injected through `Reader`.
public struct BrokerWorld: Sendable {
    /// Accepts client connections (TCP, WebSocket, or several merged).
    public let listener: Listener
    /// A periodic monotonic clock driving keep-alive, timeouts, will delays and session expiry.
    public let clock: @Sendable () -> Publisher<Duration, Never>

    /// Creates a world.
    /// - Parameters:
    ///   - listener: Accepts connections.
    ///   - clock: A periodic monotonic clock.
    public init(listener: Listener, clock: @escaping @Sendable () -> Publisher<Duration, Never>) {
        self.listener = listener
        self.clock = clock
    }

    var runtime: RuntimeWorld {
        RuntimeWorld(transport: .unavailable, listener: listener, clock: clock)
    }
}

/// An MQTT broker as a stream: subscribing starts listening, the events report what clients do,
/// and cancelling stops the broker (closing every connection).
///
/// ```swift
/// let broker: Publisher<BrokerEvent, BrokerError> =
///     MQTTBroker.serve(BrokerOptions(), policy: .open, publications: .empty()).runReader(world)
/// ```
///
/// The protocol is ``BrokerMachine/step(_:)``; this function only plugs it into the shared
/// `ConnectionRuntime`.
public enum MQTTBroker {
    /// Builds a broker.
    /// - Parameters:
    ///   - options: How the broker behaves.
    ///   - policy: Authentication and authorization decisions.
    ///   - publications: Messages the application publishes itself.
    /// - Returns: The broker, waiting for its world.
    public static func serve(
        _ options: BrokerOptions,
        policy: BrokerPolicy,
        publications: Publisher<Publish, Never>
    ) -> Reader<BrokerWorld, Publisher<BrokerEvent, BrokerError>> {
        ConnectionRuntime.run(
            initial: BrokerState.initial(options),
            step: BrokerMachine.step(policy),
            lift: BrokerInput.connection,
            external: publications.map(BrokerInput.publish),
            encodingFailure: BrokerError.encoding
        )
        .contramapEnvironment(get(\BrokerWorld.runtime))
    }
}
