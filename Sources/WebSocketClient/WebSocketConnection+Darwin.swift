#if canImport(Darwin)
import Foundation
import FP

// MARK: - URLSession factory (Apple platforms only)

extension URLSession {
    /// Returns a lazy task that, when run, opens a WebSocket to `url`.
    ///
    /// ```swift
    /// let conn = await URLSession.shared
    ///     .webSocketConnection(with: URL(string: "wss://echo.example.com")!)
    ///     .run()
    /// _ = await conn.send(.text("hello")).run()
    /// // conn goes out of scope → deinit → normal-closure frame sent
    /// ```
    public func webSocketConnection(with url: URL) -> DeferredTask<WebSocketConnection> {
        makeConnection(webSocketTask(with: url))
    }

    /// Returns a lazy task that, when run, opens a WebSocket for `request`.
    ///
    /// Use this overload for custom headers such as `Authorization`:
    ///
    /// ```swift
    /// var req = URLRequest(url: URL(string: "wss://api.example.com/ws")!)
    /// req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    /// let conn = await URLSession.shared.webSocketConnection(with: req).run()
    /// ```
    public func webSocketConnection(with request: URLRequest) -> DeferredTask<WebSocketConnection> {
        makeConnection(webSocketTask(with: request))
    }

    /// Returns a lazy task that, when run, opens a WebSocket advertising the given subprotocols.
    ///
    /// ```swift
    /// let conn = await URLSession.shared
    ///     .webSocketConnection(with: URL(string: "wss://chat.example.com")!, protocols: ["chat", "v2"])
    ///     .run()
    /// ```
    public func webSocketConnection(with url: URL, protocols: [String]) -> DeferredTask<WebSocketConnection> {
        makeConnection(webSocketTask(with: url, protocols: protocols))
    }

    // MARK: - Private factory

    private func makeConnection(_ task: URLSessionWebSocketTask) -> DeferredTask<WebSocketConnection> {
        DeferredTask {
            let box = WebSocketTaskBox(task)
            box.task.resume()
            return WebSocketConnection(
                receive: DeferredStream {
                    AsyncStream { continuation in
                        let delegate = WebSocketReceiveDelegate(box: box, continuation: continuation)
                        continuation.onTermination = { @Sendable _ in delegate.stop() }
                        delegate.start()
                    }
                },
                send: { message in
                    DeferredTask {
                        await withCheckedContinuation { continuation in
                            box.task.send(message.asTaskMessage) { error in
                                continuation.resume(returning: error.map(Result.failure) ?? .success(()))
                            }
                        }
                    }
                },
                ping: DeferredTask {
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
        case .text(let s): return .string(s)
        case .data(let d): return .data(d)
        }
    }
}

extension URLSessionWebSocketTask.Message {
    /// Returns `nil` for any `@unknown default` case added in a future SDK.
    var asWebSocketMessage: WebSocketMessage? {
        switch self {
        case .string(let s): return .text(s)
        case .data(let d):   return .data(d)
        @unknown default:    return nil
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
/// no hidden `Task`. Pure callbacks feed the `AsyncStream.Continuation`.
private final class WebSocketReceiveDelegate: @unchecked Sendable {
    private let box: WebSocketTaskBox
    private let continuation: AsyncStream<Result<WebSocketMessage, Error>>.Continuation

    init(
        box: WebSocketTaskBox,
        continuation: AsyncStream<Result<WebSocketMessage, Error>>.Continuation
    ) {
        self.box = box
        self.continuation = continuation
    }

    func start() { receiveNext() }
    func stop()  { box.task.cancel(with: .normalClosure, reason: nil) }

    private func receiveNext() {
        box.task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(message):
                if let msg = message.asWebSocketMessage {
                    continuation.yield(.success(msg))
                }
                receiveNext()
            case let .failure(error):
                continuation.yield(.failure(error))
                continuation.finish()
            }
        }
    }
}
#endif
