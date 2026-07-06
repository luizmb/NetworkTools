// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A Bonjour service identity: the combination of name, type, and domain that uniquely
/// identifies a published service on the local network.
///
/// ```swift
/// let desc = ServiceDescription(
///     serviceName: "My Speaker",
///     type: "_airplay._tcp.",
///     domain: "local."
/// )
/// ```
public struct ServiceDescription {
    /// Human-readable name advertised via Bonjour (e.g. `"Living Room Speaker"`).
    public let serviceName: String
    /// Bonjour registration domain (e.g. `"local."` or `""`).
    public let domain: String
    /// Bonjour service type in `_type._protocol.` form (e.g. `"_http._tcp."`).
    public let type: String

    public init(serviceName: String, type: String, domain: String) {
        self.serviceName = serviceName
        self.type = type
        self.domain = domain
    }

    /// Converts a ``BonjourServiceInfo`` (async API) to a `ServiceDescription` (Combine API).
    ///
    /// ```swift
    /// for await result in bonjourBrowserStream(serviceType: "_myapp._tcp.") {
    ///     if case .success(.found(let info)) = result {
    ///         let desc = ServiceDescription(info)
    ///         NWBrowserPublisher(serviceDescription: desc).sink { ... }
    ///     }
    /// }
    /// ```
    public init(_ info: BonjourServiceInfo) {
        self.init(serviceName: info.name, type: info.type, domain: info.domain)
    }
}

public extension BonjourServiceInfo {
    /// Converts a `ServiceDescription` (Combine API) to a ``BonjourServiceInfo`` (async API).
    init(_ description: ServiceDescription) {
        self.init(name: description.serviceName, type: description.type, domain: description.domain)
    }
}
