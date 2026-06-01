#if canImport(Network)
import Foundation
import Network

/// A resolved IP address — either IPv4 or IPv6.
///
/// `IP` provides a uniform representation for both address families with consistent string
/// formatting suitable for logging, display, and URL construction.
///
/// This type is used by `NWEndpointPublisher.ResolvedEndpoint` when a hostname resolves to
/// a concrete address.
///
/// ## Creating an IP address
///
/// ```swift
/// // From a string
/// let loopback = IP("127.0.0.1")   // .ipv4
/// let v6       = IP("::1")          // .ipv6
///
/// // From Network.framework address types
/// let v4 = IP(IPv4Address("10.0.0.1")!)
/// let v6 = IP(IPv6Address("fe80::1")!)
/// ```
///
/// ## Displaying
///
/// ```swift
/// print(ip.ipString)    // "192.168.1.1"
/// print(ip.ipUrlString) // "192.168.1.1" for v4, "[fe80::1]" for v6
/// ```
public enum IP: Codable, CustomStringConvertible, Equatable, Hashable { // swiftlint:disable:this type_name
    case ipv4(IPv4Address)
    case ipv6(IPv6Address)

    // MARK: - Accessors

    public var genericIP: IPAddress {
        switch self {
        case let .ipv4(v4): v4
        case let .ipv6(v6): v6
        }
    }

    public var description: String { ipString }

    /// Standard dotted-decimal (IPv4) or colon-separated (IPv6) string.
    public var ipString: String {
        switch self {
        case let .ipv4(v4):
            return v4.rawValue.map(String.init).joined(separator: ".")
        case let .ipv6(v6):
            let bigEndian = (1 == CFSwapInt32LittleToHost(1))
            var address = (0..<8)
                .map { i in v6.rawValue.subdata(in: i * 2 ..< i * 2 + 2).readUInt16(bigEndian: bigEndian) }
                .map { $0 == 0 ? "" : String(format: "%llx", $0) }
                .joined(separator: ":")
            while address.contains(":::") { address = address.replacingOccurrences(of: ":::", with: "::") }
            if let name = v6.interface?.name { return "\(address)%\(name)" }
            return address
        }
    }

    /// URL-safe representation: IPv6 addresses are wrapped in brackets per RFC 3986.
    public var ipUrlString: String {
        switch self {
        case .ipv4: ipString
        case .ipv6: "[\(ipString)]"
        }
    }

    // MARK: - Initialisers

    /// Parses an IP address string, trying IPv6 first then IPv4.
    public init?(_ ipString: String) {
        if let a = IPv6Address(ipString) { self = .ipv6(a) }
        else if let a = IPv4Address(ipString) { self = .ipv4(a) }
        else { return nil }
    }

    public init(_ ipv4: IPv4Address) { self = .ipv4(ipv4) }
    public init(_ ipv6: IPv6Address) { self = .ipv6(ipv6) }

    /// Parses raw address bytes — 4 bytes for IPv4, 16 for IPv6.
    public init?(_ data: Data) {
        if let a = IPv6Address(data) { self = .ipv6(a) }
        else if let a = IPv4Address(data) { self = .ipv4(a) }
        else { return nil }
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let bytes = try c.decode(Data.self)
        if bytes.count == 4 {
            guard let v4 = IPv4Address(bytes) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "Can't parse IPv4 from \(bytes)")
            }
            self = .ipv4(v4)
        } else {
            guard let v6 = IPv6Address(bytes) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "Can't parse IPv6 from \(bytes)")
            }
            self = .ipv6(v6)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(genericIP.rawValue)
    }
}

// MARK: - IP prisms

extension IP {
    public var ipv4: IPv4Address? {
        guard case let .ipv4(v) = self else { return nil }
        return v
    }

    public var isIPv4: Bool { ipv4 != nil }

    public var ipv6: IPv6Address? {
        guard case let .ipv6(v) = self else { return nil }
        return v
    }

    public var isIPv6: Bool { ipv6 != nil }
}

extension Array where Element == IP {
    /// Picks the first IPv6 address, falling back to the first IPv4 address.
    public var preferredAddress: IP? {
        first(where: \.isIPv6) ?? first(where: \.isIPv4)
    }
}

// MARK: - Data helpers (inlined from FoundationExtensions)

private extension Data {
    func subdata(start: Int, length: Int) -> Data { subdata(in: start ..< start + length) }

    func readUInt16(bigEndian: Bool) -> UInt16 {
        let v: UInt16 = withUnsafeBytes { $0.load(as: UInt16.self) }
        return bigEndian ? v.bigEndian : v
    }
}
#endif
