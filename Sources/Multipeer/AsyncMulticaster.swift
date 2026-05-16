#if canImport(MultipeerConnectivity)
import Foundation

/// Minimal lock-protected multicaster that fans a single delegate-driven event source out to
/// multiple `AsyncStream` consumers.
///
/// Each call to ``register()`` creates a fresh `AsyncStream` whose continuation is added to the
/// active set and removed on termination. Calls to ``send(_:)`` yield the value to every
/// currently-registered continuation.
///
/// This is the DeferredStream-side counterpart to Combine's `PassthroughSubject` and is used by
/// ``MultipeerSession`` to expose `messagesStream` / `connectionsStream` independently from the
/// Combine subjects.
final class AsyncMulticaster<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]

    func register() -> AsyncStream<Element> {
        AsyncStream<Element> { continuation in
            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            lock.unlock()
            continuation.onTermination = { @Sendable [weak self] _ in
                guard let self else { return }
                lock.lock()
                continuations[id] = nil
                lock.unlock()
            }
        }
    }

    func send(_ value: Element) {
        lock.lock()
        let snapshot = Array(continuations.values)
        lock.unlock()
        for continuation in snapshot {
            continuation.yield(value)
        }
    }

    func finish() {
        lock.lock()
        let snapshot = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()
        for continuation in snapshot {
            continuation.finish()
        }
    }
}
#endif
