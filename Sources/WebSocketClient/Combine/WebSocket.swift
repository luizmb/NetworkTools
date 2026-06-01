#if canImport(Combine)
import Combine
import Foundation

/// A handle to a full-duplex WebSocket connection with a Combine-based API.
///
/// `WebSocket` wraps a `URLSessionWebSocketTaskProtocol` and exposes three operations:
///
/// - `publisher` — subscribe to receive inbound messages as a stream
/// - `send(_:)` — lazily send a text or binary message
/// - `ping()` / `startPinging(every:)` — health-check the connection
///
/// ## Lifecycle
///
/// The underlying task starts (`.resume()` is called) when the first subscriber signals
/// demand on `publisher`. Sending works independently once the task is running, but callers
/// should subscribe to `publisher` first to guarantee the task is live before sending.
///
/// ## Combine usage
///
/// ```swift
/// var cancellables = Set<AnyCancellable>()
///
/// let socket = URLSession.shared.webSocket(with: URL(string: "wss://echo.example.com")!)
///
/// // 1. Start receiving (this resumes the task)
/// socket.publisher
///     .sink(
///         receiveCompletion: { print("done:", $0) },
///         receiveValue: { message in
///             if case .text(let text) = message { print("←", text) }
///         }
///     )
///     .store(in: &cancellables)
///
/// // 2. Send a message — lazy: network write happens when subscribed
/// socket.send("hello")
///     .sink(receiveCompletion: { _ in }, receiveValue: { print("sent") })
///     .store(in: &cancellables)
///
/// // 3. Keep the connection alive with periodic pings
/// socket.startPinging(every: 30)
///     .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
///     .store(in: &cancellables)
/// ```
///
/// ## Echo round-trip example
///
/// ```swift
/// socket.publisher
///     .compactMap { message -> String? in
///         guard case .text(let text) = message else { return nil }
///         return text
///     }
///     .flatMap(maxPublishers: .max(1)) { echo in
///         socket.send("got echo: \(echo)")
///     }
///     .sink(receiveCompletion: { _ in }, receiveValue: { })
///     .store(in: &cancellables)
/// ```
public class WebSocket: @unchecked Sendable {
    private let task: URLSessionWebSocketTaskProtocol

    init(task: URLSessionWebSocketTaskProtocol) {
        self.task = task
    }

    /// A publisher that streams every inbound message from the server.
    ///
    /// The connection starts on first subscriber demand. Cancelling the subscription
    /// closes the connection with a normal-closure frame.
    public var publisher: WebSocketPublisher {
        task.publisher
    }

    // MARK: - Sending

    /// Returns a lazy publisher that sends `string` when subscribed.
    ///
    /// The send is **deferred** — no network write happens until a subscriber attaches.
    ///
    /// ```swift
    /// socket.send("ping")
    ///     .sink(receiveCompletion: { _ in }, receiveValue: { print("sent") })
    ///     .store(in: &cancellables)
    /// ```
    public func send(_ string: String) -> Deferred<Future<Void, Error>> {
        Deferred {
            Future { completion in
                nonisolated(unsafe) let c = completion
                self.task.send(.string(string)) { error in c(error.map(Result.failure) ?? .success(())) }
            }
        }
    }

    /// Returns a lazy publisher that sends `data` when subscribed.
    ///
    /// ```swift
    /// socket.send(Data([0x01, 0x02, 0x03]))
    ///     .sink(receiveCompletion: { _ in }, receiveValue: { print("sent") })
    ///     .store(in: &cancellables)
    /// ```
    public func send(_ data: Data) -> Deferred<Future<Void, Error>> {
        Deferred {
            Future { completion in
                nonisolated(unsafe) let c = completion
                self.task.send(.data(data)) { error in c(error.map(Result.failure) ?? .success(())) }
            }
        }
    }

    // MARK: - Ping

    /// Returns a lazy publisher that sends a single ping when subscribed, completing on pong.
    ///
    /// ```swift
    /// socket.ping()
    ///     .sink(receiveCompletion: { print("ping result:", $0) }, receiveValue: { })
    ///     .store(in: &cancellables)
    /// ```
    public func ping() -> Deferred<Future<Void, Error>> {
        Deferred {
            Future { completion in
                nonisolated(unsafe) let c = completion
                self.task.sendPing { error in c(error.map(Result.failure) ?? .success(())) }
            }
        }
    }

    /// Returns a publisher that sends a ping on a fixed interval.
    ///
    /// Each ping fires at most one at a time (`maxPublishers: .max(1)`), so a slow pong
    /// never causes ping storms.
    ///
    /// ```swift
    /// // Ping every 30 s; cancel if the server stops responding
    /// socket.startPinging(every: 30)
    ///     .timeout(5, scheduler: DispatchQueue.main)
    ///     .sink(
    ///         receiveCompletion: { if case .failure = $0 { socket.publisher.cancel() } },
    ///         receiveValue: { _ in }
    ///     )
    ///     .store(in: &cancellables)
    /// ```
    public func startPinging(every interval: TimeInterval) -> AnyPublisher<Void, Error> {
        Timer
            .publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .mapError { _ -> Error in }
            .flatMap(maxPublishers: .max(1)) { [weak self] _ -> AnyPublisher<Void, Error> in
                guard let self else { return Empty().eraseToAnyPublisher() }
                return ping().eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }
}
#endif
