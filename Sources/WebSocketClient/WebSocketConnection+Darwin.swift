// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin)
import Foundation
import FP
import ReactiveConcurrency

// MARK: - URLSession factory (Apple platforms only)

public extension URLSession {
    /// Returns a lazy `Publisher` that, when subscribed, opens a WebSocket to `url`.
    ///
    /// ```swift
    /// let conn = await URLSession.shared
    ///     .webSocketConnection(with: URL(string: "wss://echo.example.com")!)
    ///     .firstResultTask().run()
    /// ```
    func webSocketConnection(with url: URL) -> Publisher<WebSocketConnection, Never> {
        makeConnection(webSocketTask(with: url))
    }

    /// Returns a lazy `Publisher` that, when subscribed, opens a WebSocket for `request`.
    ///
    /// Use this overload for custom headers such as `Authorization`.
    func webSocketConnection(with request: URLRequest) -> Publisher<WebSocketConnection, Never> {
        makeConnection(webSocketTask(with: request))
    }

    /// Returns a lazy `Publisher` that, when subscribed, opens a WebSocket advertising the given subprotocols.
    func webSocketConnection(with url: URL, protocols: [String]) -> Publisher<WebSocketConnection, Never> {
        makeConnection(webSocketTask(with: url, protocols: protocols))
    }

    // MARK: - Private factory

    private func makeConnection(_ task: URLSessionWebSocketTask) -> Publisher<WebSocketConnection, Never> {
        Publisher.future {
            let box = WebSocketTaskBox(task)
            box.task.resume()
            return WebSocketConnection(
                // `.share()` multicasts the single underlying `task.receive` loop: multiple subscribers
                // each get every message, instead of competing for (and splitting) the message stream.
                receive: Publisher { continuation in
                    let delegate = WebSocketReceiveDelegate(box: box, continuation: continuation)
                    delegate.start()
                    await continuation.suspendUntilCancelled()
                    delegate.stop()
                }.share(),
                send: { message in
                    Publisher.future {
                        await withCheckedContinuation { continuation in
                            box.task.send(message.asTaskMessage) { error in
                                continuation.resume(returning: error.map(Result.failure) ?? .success(()))
                            }
                        }
                    }
                },
                ping: Publisher.future {
                    await withCheckedContinuation { continuation in
                        box.task.sendPing { error in
                            continuation.resume(returning: error.map(Result.failure) ?? .success(()))
                        }
                    }
                },
                cancel: { box.task.cancel(with: .normalClosure, reason: nil) }
            )
        }
    }
}

// MARK: - Message conversion

extension WebSocketMessage {
    var asTaskMessage: URLSessionWebSocketTask.Message {
        switch self {
        case let .text(s): .string(s)
        case let .data(d): .data(d)
        }
    }
}

extension URLSessionWebSocketTask.Message {
    /// Returns `nil` for any `@unknown default` case added in a future SDK.
    var asWebSocketMessage: WebSocketMessage? {
        switch self {
        case let .string(s): return .text(s)
        case let .data(d): return .data(d)
        @unknown default: return nil
        }
    }
}

// MARK: - Private helpers

/// Boxes `URLSessionWebSocketTask` (not formally `Sendable`) for safe capture in
/// `@Sendable` closures. Thread-safety is guaranteed by `URLSessionWebSocketTask` itself.
private final class WebSocketTaskBox: @unchecked Sendable {
    let task: URLSessionWebSocketTask
    init(_ task: URLSessionWebSocketTask) { self.task = task }
}

/// Drives the recursive receive loop via completion-handler callbacks — no `async`/`await`,
/// no hidden `Task`. Pure callbacks feed the `Publisher.Continuation`.
private final class WebSocketReceiveDelegate: @unchecked Sendable {
    private let box: WebSocketTaskBox
    private let continuation: Publisher<WebSocketMessage, Error>.Continuation

    init(
        box: WebSocketTaskBox,
        continuation: Publisher<WebSocketMessage, Error>.Continuation
    ) {
        self.box = box
        self.continuation = continuation
    }

    func start() { receiveNext() }
    func stop() { box.task.cancel(with: .normalClosure, reason: nil) }

    private func receiveNext() {
        box.task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(message):
                if let msg = message.asWebSocketMessage {
                    continuation.yield(msg)
                }
                receiveNext()
            case let .failure(error):
                continuation.fail(error)
            }
        }
    }
}
#endif
