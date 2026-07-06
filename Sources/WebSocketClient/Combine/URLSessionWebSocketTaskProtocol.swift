// SPDX-License-Identifier: Apache-2.0

#if canImport(Combine)
import Foundation

/// Abstraction over `URLSessionWebSocketTask` that enables unit-testing of WebSocket
/// publishers without opening a real network connection.
///
/// `URLSessionWebSocketTask` conforms to this protocol out of the box, so production code
/// passes a real task while tests supply a mock.
///
/// ## Mocking in tests
///
/// ```swift
/// final class MockWebSocketTask: URLSessionWebSocketTaskProtocol {
///     var sentMessages: [URLSessionWebSocketTask.Message] = []
///     var receiveHandler: ((Result<URLSessionWebSocketTask.Message, Error>) -> Void)?
///
///     func resume() {}
///     func cancel(with code: URLSessionWebSocketTask.CloseCode, reason: Data?) {}
///
///     func send(_ message: URLSessionWebSocketTask.Message,
///               completionHandler: @escaping (Error?) -> Void) {
///         sentMessages.append(message)
///         completionHandler(nil)
///     }
///
///     func receive(completionHandler: @escaping (Result<URLSessionWebSocketTask.Message, Error>) -> Void) {
///         receiveHandler = completionHandler
///     }
///
///     func sendPing(pongReceiveHandler: @escaping (Error?) -> Void) {
///         pongReceiveHandler(nil)
///     }
/// }
/// ```
public protocol URLSessionWebSocketTaskProtocol {
    func sendPing(pongReceiveHandler: @escaping @Sendable (Error?) -> Void)
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
    func send(_ message: URLSessionWebSocketTask.Message, completionHandler: @escaping @Sendable (Error?) -> Void)
    func receive(completionHandler: @escaping @Sendable (Result<URLSessionWebSocketTask.Message, Error>) -> Void)
    func resume()
}

extension URLSessionWebSocketTask: URLSessionWebSocketTaskProtocol {}
#endif
