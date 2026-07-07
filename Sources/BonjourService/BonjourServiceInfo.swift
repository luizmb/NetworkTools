// SPDX-License-Identifier: Apache-2.0

// nil TXT (no record) is semantically distinct from [:] (empty record).
// swiftlint:disable discouraged_optional_collection
import Foundation

/// Platform-agnostic description of a discovered Bonjour service.
///
/// `BonjourServiceInfo` is the element type of ``BonjourBrowseEvent`` and replaces
/// `NWEndpoint` in the browsing API, making browse results safe to
/// reference from Linux and other non-Apple platforms.
///
/// Note that `host` and `port` are not populated from browsing alone — Bonjour
/// discovery gives you the service identity (name, type, domain, TXT record); a
/// separate resolution step is required to obtain the IP address and port.
///
/// ```swift
/// for await result in bonjourBrowserStream(serviceType: "_myapp._tcp.") {
///     if case .success(.found(let info)) = result {
///         print("name:", info.name)
///         print("txt:",  info.txt ?? [:])
///     }
/// }
/// ```
public struct BonjourServiceInfo: Sendable, Equatable {
    /// The service instance name (e.g. `"My Speaker"`).
    public let name: String
    /// Bonjour service type (e.g. `"_myapp._tcp."`).
    public let type: String
    /// Registration domain (e.g. `"local."`).
    public let domain: String
    /// TXT record key-value pairs, or `nil` when no TXT record was published.
    public let txt: [String: String]?

    public init(name: String, type: String, domain: String, txt: [String: String]? = nil) {
        self.name = name
        self.type = type
        self.domain = domain
        self.txt = txt
    }
}

// swiftlint:enable discouraged_optional_collection
