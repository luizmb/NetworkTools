#if canImport(Combine)
import Foundation

extension URLSession {
    /// Creates a `WebSocket` handle for the given URL.
    ///
    /// The underlying `URLSessionWebSocketTask` is created immediately but does **not**
    /// start until the first subscriber demands values from `webSocket.publisher`.
    ///
    /// ```swift
    /// let socket = URLSession.shared.webSocket(with: URL(string: "wss://echo.example.com")!)
    /// ```
    public func webSocket(with url: URL) -> WebSocket {
        WebSocket(task: webSocketTask(with: url))
    }

    /// Creates a `WebSocket` handle for the given `URLRequest`.
    ///
    /// Use this overload when you need to set custom headers (e.g. `Authorization`):
    ///
    /// ```swift
    /// var request = URLRequest(url: URL(string: "wss://api.example.com/ws")!)
    /// request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    /// let socket = URLSession.shared.webSocket(with: request)
    /// ```
    public func webSocket(with request: URLRequest) -> WebSocket {
        WebSocket(task: webSocketTask(with: request))
    }

    /// Creates a `WebSocket` handle advertising the given subprotocols.
    ///
    /// ```swift
    /// let socket = URLSession.shared.webSocket(
    ///     with: URL(string: "wss://echo.example.com")!,
    ///     protocols: ["chat", "v2"]
    /// )
    /// ```
    public func webSocket(with url: URL, protocols: [String]) -> WebSocket {
        WebSocket(task: webSocketTask(with: url, protocols: protocols))
    }
}
#endif
