// SPDX-License-Identifier: Apache-2.0

#if canImport(Network)
import Foundation
import FP
@preconcurrency import Network
import ReactiveConcurrency

// MARK: - NWConnection factory (Apple platforms only)

extension NWConnection {
    /// Starts this connection and wraps it as a ``BonjourConnection``.
    ///
    /// Called automatically by ``bonjourListenerStream`` for every inbound connection;
    /// you should not normally need to call this directly.
    func asBonjourConnection(startOn queue: DispatchQueue = .main) -> BonjourConnection {
        start(queue: queue)
        let box = NWConnectionBox(self)
        return BonjourConnection(
            receive: Publisher { continuation in
                let delegate = NWConnectionReceiveDelegate(box: box, continuation: continuation)
                delegate.start()
                await continuation.suspendUntilCancelled()
                delegate.stop()
            },
            send: { data in
                Publisher.future {
                    await withCheckedContinuation { continuation in
                        box.connection.send(content: data, completion: .contentProcessed { error in
                            continuation.resume(returning: error.map(Result.failure) ?? .success(()))
                        })
                    }
                }
            },
            cancel: { box.connection.cancel() }
        )
    }
}

// MARK: - Private helpers

/// Boxes `NWConnection` for safe capture in `@Sendable` closures.
private final class NWConnectionBox: @unchecked Sendable {
    let connection: NWConnection
    init(_ connection: NWConnection) { self.connection = connection }
}

/// Drives the recursive receive loop via completion callbacks — no `async`/`await`,
/// no hidden `Task`. Pure callbacks feed the `Publisher.Continuation`.
private final class NWConnectionReceiveDelegate: @unchecked Sendable {
    private let box: NWConnectionBox
    private let continuation: Publisher<Data, Error>.Continuation

    init(box: NWConnectionBox, continuation: Publisher<Data, Error>.Continuation) {
        self.box = box
        self.continuation = continuation
    }

    func start() { receiveNext() }
    func stop() { box.connection.cancel() }

    private func receiveNext() {
        box.connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                continuation.fail(error)
                return
            }
            if let data, !data.isEmpty {
                continuation.yield(data)
            }
            if isComplete {
                continuation.finish()
                return
            }
            receiveNext()
        }
    }
}
#endif
