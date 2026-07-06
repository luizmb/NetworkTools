// SPDX-License-Identifier: Apache-2.0

#if canImport(Combine)
import Combine
import Core
import Foundation

/// A Combine `Publisher` that streams inbound messages from a WebSocket connection.
///
/// `WebSocketPublisher` wraps the completion-handler-based `URLSessionWebSocketTask.receive`
/// API into a Combine stream. It respects backpressure via `DemandBuffer`: messages that
/// arrive faster than the subscriber requests them are queued and delivered in order.
///
/// The underlying task is started lazily — `.resume()` is called only when the first
/// subscriber signals demand, not at subscription time.
///
/// ## Combine usage
///
/// Obtain a `WebSocketPublisher` via `URLSession.webSocket(with:)` and its `.publisher`
/// property, or directly from any `URLSessionWebSocketTaskProtocol`:
///
/// ```swift
/// var cancellables = Set<AnyCancellable>()
///
/// // Via URLSession convenience
/// let socket = URLSession.shared.webSocket(with: URL(string: "wss://echo.example.com")!)
///
/// socket.publisher
///     .sink(
///         receiveCompletion: { completion in
///             switch completion {
///             case .finished:       print("connection closed normally")
///             case .failure(let e): print("error:", e)
///             }
///         },
///         receiveValue: { message in
///             switch message {
///             case .text(let text):  print("text:", text)
///             case .data(let bytes): print("binary:", bytes.count, "bytes")
///             }
///         }
///     )
///     .store(in: &cancellables)
/// ```
///
/// ## Sending while receiving
///
/// ```swift
/// socket.publisher
///     .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
///     .store(in: &cancellables)
///
/// // The task is now running; sends work immediately
/// socket.send("hello, server")
///     .sink(receiveCompletion: { _ in }, receiveValue: { })
///     .store(in: &cancellables)
/// ```
public struct WebSocketPublisher {
    private let task: URLSessionWebSocketTaskProtocol

    public init(task: URLSessionWebSocketTaskProtocol) {
        self.task = task
    }
}

extension WebSocketPublisher: Publisher {
    public typealias Output = WebSocketMessage
    public typealias Failure = Error

    public func receive<S>(subscriber: S)
    where S: Subscriber, Failure == S.Failure, Output == S.Input {
        subscriber.receive(subscription: Subscription(subscriber: subscriber, task: task))
    }
}

extension WebSocketPublisher {
    private class Subscription<S: Subscriber>: NSObject, Combine.Subscription, @unchecked Sendable
    where S.Input == Output, S.Failure == Failure {
        private var buffer: DemandBuffer<S>?
        private let task: URLSessionWebSocketTaskProtocol
        private let lock = NSRecursiveLock()
        private var started = false

        init(subscriber: S, task: URLSessionWebSocketTaskProtocol) {
            self.task = task
            buffer = DemandBuffer(subscriber: subscriber)
            super.init()
        }

        func request(_ demand: Subscribers.Demand) {
            guard let buffer else { return }
            lock.lock()
            if !started, demand > .none {
                started = true
                lock.unlock()
                start()
            } else {
                lock.unlock()
            }
            _ = buffer.demand(demand)
        }

        func cancel() {
            buffer = nil
            started = false
            stop()
        }

        private func start() {
            receiveNext()
            task.resume()
        }

        private func stop() {
            task.cancel(with: .normalClosure, reason: nil)
            buffer?.complete(completion: .finished)
        }

        private func receiveNext() {
            task.receive { [weak self] result in
                guard let self else { return }
                switch result {
                case let .success(message):
                    if let msg = message.asWebSocketMessage { _ = buffer?.buffer(value: msg) }
                    receiveNext()
                case let .failure(error):
                    buffer?.complete(completion: .failure(error))
                }
            }
        }
    }
}
#endif
