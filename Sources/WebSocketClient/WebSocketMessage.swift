// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A platform-agnostic WebSocket message — either text or binary.
///
/// `WebSocketMessage` is the element type of ``WebSocketConnection/receive`` and
/// the parameter type of ``WebSocketConnection/send``. Using this type instead of
/// `URLSessionWebSocketTask.Message` lets the connection API compile and be
/// referenced on any platform, including Linux, while the Apple implementation
/// converts to and from the Foundation type internally.
///
/// ## Pattern matching
///
/// ```swift
/// for await result in connection.receive {
///     switch result {
///     case .success(.text(let text)): print("←", text)
///     case .success(.data(let bytes)): print("← \(bytes.count) bytes")
///     case .failure(let err): print("error:", err)
///     }
/// }
/// ```
public enum WebSocketMessage: Sendable, Equatable {
    /// A UTF-8 text frame.
    case text(String)
    /// A binary data frame.
    case data(Data)
}
