#if canImport(Combine)
import Foundation

extension URLSessionWebSocketTaskProtocol {
    /// A Combine publisher that streams inbound WebSocket messages.
    ///
    /// Equivalent to creating `WebSocketPublisher(task: self)` directly. The connection
    /// starts (`.resume()` is called) on the first subscriber demand, not at creation time.
    ///
    /// ```swift
    /// let task: URLSessionWebSocketTaskProtocol = URLSession.shared
    ///     .webSocketTask(with: URL(string: "wss://echo.example.com")!)
    ///
    /// task.publisher
    ///     .sink { completion in print("done:", completion) }
    ///          receiveValue: { message in print("got:", message) }
    ///     .store(in: &cancellables)
    /// ```
    var publisher: WebSocketPublisher {
        .init(task: self)
    }
}
#endif
