// SPDX-License-Identifier: Apache-2.0

import ReactiveConcurrency

/// The effects a runtime needs, injected through `Reader` by the client, broker and bridge.
public struct RuntimeWorld: Sendable {
    /// Opens outgoing connections (clients, bridges).
    public let transport: Transport
    /// Accepts incoming connections (brokers).
    public let listener: Listener
    /// A periodic monotonic clock: emits the current time as elapsed time since an arbitrary
    /// origin, at the resolution the machine needs (e.g. every 250 ms).
    public let clock: @Sendable () -> Publisher<Duration, Never>
    /// The transport to the server an MQTT 5 Server Reference names (e.g. `"other.example.com:1883"`),
    /// or `nil` to not follow redirects to it.
    public let redirect: @Sendable (_ serverReference: String) -> Transport?

    /// Creates a world.
    /// - Parameters:
    ///   - transport: Opens outgoing connections.
    ///   - listener: Accepts incoming connections.
    ///   - clock: A periodic monotonic clock.
    ///   - redirect: Transports for server references; by default redirects are not followed.
    public init(
        transport: Transport,
        listener: Listener,
        clock: @escaping @Sendable () -> Publisher<Duration, Never>,
        redirect: @escaping @Sendable (_ serverReference: String) -> Transport? = { _ in nil }
    ) {
        self.transport = transport
        self.listener = listener
        self.clock = clock
        self.redirect = redirect
    }
}

public extension Publisher where Output == Duration, Failure == Never {
    /// A clock for ``RuntimeWorld/clock``: emits the elapsed time of `clock` every `interval`,
    /// starting from zero at subscription.
    /// - Parameters:
    ///   - interval: The tick period.
    ///   - clock: The clock to measure with, e.g. `ContinuousClock()`.
    /// - Returns: The tick publisher.
    static func monotonicTicks<C: Clock & Sendable>(every interval: Duration, clock: C) -> Publisher<Duration, Never>
    where C.Duration == Duration {
        Publisher<C.Instant, Never>.timer(every: interval, clock: clock)
            .scan((origin: C.Instant?.none, elapsed: Duration.zero)) { acc, instant in
                let origin = acc.origin ?? instant
                return (origin: origin, elapsed: origin.duration(to: instant))
            }
            .map(\.elapsed)
    }
}
