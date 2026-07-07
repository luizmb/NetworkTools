// SPDX-License-Identifier: Apache-2.0

#if canImport(MultipeerConnectivity)
import Foundation

/// Minimal lock-protected **hot subject**: a single delegate-driven event source fanned out to
/// multiple subscribers, sharing emissions.
///
/// This is the one place that uses `AsyncStream` directly, deliberately: RC `Publisher` is *cold* and
/// *unicast*, whereas a subject must register subscribers **eagerly** and multicast — which is
/// load-bearing for ``MultipeerSession``'s `inviteTask`, which registers before issuing the invite so
/// the connection event can't be lost to a race. ``MultipeerSession`` wraps each ``register()`` in an
/// RC `Publisher`, so the subject stays an internal implementation detail.
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
