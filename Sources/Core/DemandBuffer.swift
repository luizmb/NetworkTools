#if canImport(Combine)
import Combine
import class Foundation.NSRecursiveLock

/// Backpressure-aware buffer that sits between an upstream source and a Combine subscriber.
///
/// `DemandBuffer` decouples the rate at which values arrive from the rate at which a downstream
/// subscriber requests them. Values are stored in an internal queue and flushed whenever the
/// subscriber signals additional demand via `request(_:)`.
///
/// This implementation is sourced from [CombineExt](https://github.com/CombineExt/CombineExt)
/// and is vendored here to remove the external dependency.
///
/// ## Usage
///
/// Inside a `Subscription` implementation, create one buffer per subscriber and route all
/// upstream events through it:
///
/// ```swift
/// private class MySubscription<S: Subscriber>: Subscription {
///     private var buffer: DemandBuffer<S>?
///
///     init(subscriber: S) {
///         buffer = DemandBuffer(subscriber: subscriber)
///     }
///
///     func request(_ demand: Subscribers.Demand) {
///         _ = buffer?.demand(demand)
///         if !started { start() }
///     }
///
///     func cancel() { buffer = nil; stop() }
///
///     // From delegate / callback:
///     func received(_ value: S.Input) { _ = buffer?.buffer(value: value) }
///     func completed(_ completion: Subscribers.Completion<S.Failure>) {
///         buffer?.complete(completion: completion)
///     }
/// }
/// ```
package class DemandBuffer<S: Subscriber> {
    private let lock = NSRecursiveLock()
    private var buffer = [S.Input]()
    private let subscriber: S
    private var completion: Subscribers.Completion<S.Failure>?
    private var demandState = Demand()

    package init(subscriber: S) {
        self.subscriber = subscriber
    }

    /// Buffer a value from upstream; delivers immediately if there is outstanding demand.
    @discardableResult
    package func buffer(value: S.Input) -> Subscribers.Demand {
        precondition(completion == nil, "Upstream sent a value after completion")
        switch demandState.requested {
        case .unlimited: return subscriber.receive(value)
        default:
            buffer.append(value)
            return flush()
        }
    }

    /// Signal completion from upstream; flushes remaining buffered values first.
    package func complete(completion: Subscribers.Completion<S.Failure>) {
        precondition(self.completion == nil, "Upstream completed more than once")
        self.completion = completion
        _ = flush()
    }

    /// Called by the subscriber's `request(_:)` to register new demand; triggers a flush.
    package func demand(_ demand: Subscribers.Demand) -> Subscribers.Demand {
        flush(adding: demand)
    }

    private func flush(adding newDemand: Subscribers.Demand? = nil) -> Subscribers.Demand {
        lock.lock()
        defer { lock.unlock() }

        if let d = newDemand { demandState.requested += d }

        guard demandState.requested > 0 || newDemand == Subscribers.Demand.none else { return .none }

        while !buffer.isEmpty && demandState.processed < demandState.requested {
            demandState.requested += subscriber.receive(buffer.remove(at: 0))
            demandState.processed += 1
        }

        if let completion {
            buffer = []
            demandState = .init()
            self.completion = nil
            subscriber.receive(completion: completion)
            return .none
        }

        let sent = demandState.requested - demandState.sent
        demandState.sent += sent
        return sent
    }

    private struct Demand {
        var processed: Subscribers.Demand = .none
        var requested: Subscribers.Demand = .none
        var sent: Subscribers.Demand = .none
    }
}

extension Subscription {
    func requestIfNeeded(_ demand: Subscribers.Demand) {
        guard demand > .none else { return }
        request(demand)
    }
}

extension Optional where Wrapped == Subscription {
    mutating func kill() {
        self?.cancel()
        self = nil
    }
}
#endif
