// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Events emitted by ``bonjourListenerStream(serviceType:serviceName:port:txtRecord:params:)``.
///
/// All cases use platform-agnostic types: `UInt16` for the port and
/// ``BonjourConnection`` for accepted connections, so the type is safe to
/// reference from any platform.
///
/// ```swift
/// for await result in bonjourListenerStream(serviceType: "_myapp._tcp.") {
///     switch result {
///     case .success(.ready(let port)):
///         print("advertising on port", port ?? 0)
///     case .success(.newConnection(let conn)):
///         Task { for await data in conn.receive { ... } }
///     case .success(.registered):
///         print("Bonjour registration confirmed")
///     case .success(.unregistered):
///         print("Bonjour registration removed")
///     case .failure(let err):
///         print("listener error:", err)
///     }
/// }
/// ```
public enum BonjourListenEvent: Sendable {
    /// The listener is active and advertising via Bonjour. `port` is the
    /// OS-assigned port — always read this when created with port 0.
    case ready(port: UInt16?)
    /// A client connected. Use the ``BonjourConnection`` to send and receive.
    case newConnection(BonjourConnection)
    /// The Bonjour service registration was confirmed on the local network.
    case registered
    /// The Bonjour service registration was removed from the local network.
    case unregistered
}

/// Errors emitted by ``bonjourListenerStream(serviceType:serviceName:port:txtRecord:params:)``.
public enum BonjourListenError: Error {
    /// Local network access was denied by the OS or user.
    case permissionDenied
    /// The listener failed with an underlying error.
    case failed(error: Error)
}
