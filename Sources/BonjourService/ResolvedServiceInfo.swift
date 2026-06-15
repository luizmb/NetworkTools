// swiftlint:disable discouraged_optional_collection
import Foundation

/// The concrete address information for a resolved Bonjour service.
///
/// Obtained by running a ``bonjourResolve(_:timeout:)`` task after discovering a
/// service via ``bonjourBrowserStream``. `ResolvedServiceInfo` gives you the
/// hostname, IP addresses, and port needed to open a WebSocket or other connection.
///
/// ```swift
/// // Discover → resolve → connect
/// for await result in bonjourBrowserStream(serviceType: "_myapp._tcp.") {
///     guard case .success(.found(let info)) = result else { continue }
///     let resolved = try await bonjourResolve(info).run().get()
///     let url = resolved.webSocketURL()!
///     let conn = await URLSession.shared.webSocketConnection(with: url).run()
///     _ = await conn.send(.text("hello")).run()
/// }
/// ```
public struct ResolvedServiceInfo: Sendable, Equatable {
    /// Service instance name (same as ``BonjourServiceInfo/name``).
    public let name: String
    /// Bonjour service type (same as ``BonjourServiceInfo/type``).
    public let type: String
    /// Registration domain (same as ``BonjourServiceInfo/domain``).
    public let domain: String
    /// Resolved hostname, if available (e.g. `"macbook.local"`).
    public let host: String?
    /// Resolved IP address strings — may include both IPv4 and IPv6.
    public let ips: [String]
    /// Port number, or `nil` if resolution didn't provide one.
    public let port: UInt16?
    /// TXT record key-value pairs, or `nil` when no TXT record was published.
    public let txt: [String: String]?

    public init(
        name: String,
        type: String,
        domain: String,
        host: String?,
        port: UInt16?,
        ips: [String] = [],
        txt: [String: String]? = nil
    ) {
        self.name = name
        self.type = type
        self.domain = domain
        self.host = host
        self.port = port
        self.ips = ips
        self.txt = txt
    }
}

// MARK: - Convenience

extension ResolvedServiceInfo {
    /// The preferred host string for opening a connection.
    ///
    /// Returns the first resolved IP address if available, falling back to the
    /// hostname. IPv6 addresses are returned without brackets here; use
    /// ``webSocketURL(path:secure:)`` to get a properly formatted URL.
    public var preferredHost: String? { ips.first ?? host }

    /// Returns a WebSocket URL built from the resolved host and port.
    ///
    /// IPv6 addresses are automatically wrapped in brackets per RFC 3986.
    ///
    /// ```swift
    /// let url = resolved.webSocketURL()           // ws://192.168.1.10:8080
    /// let secureURL = resolved.webSocketURL(secure: true)  // wss://...
    /// let pathURL = resolved.webSocketURL(path: "/ws")     // ws://.../ws
    /// ```
    public func webSocketURL(path: String = "", secure: Bool = false) -> URL? {
        guard let rawHost = preferredHost, let port else { return nil }
        let scheme = secure ? "wss" : "ws"
        let host = rawHost.contains(":") ? "[\(rawHost)]" : rawHost
        return URL(string: "\(scheme)://\(host):\(port)\(path)")
    }
}
// swiftlint:enable discouraged_optional_collection
