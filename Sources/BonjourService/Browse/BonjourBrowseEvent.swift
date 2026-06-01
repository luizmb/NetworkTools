// nil TXT (no record) is semantically distinct from [:] (empty record).
// swiftlint:disable discouraged_optional_collection
import Foundation

/// Events emitted by ``bonjourBrowserStream(serviceType:domain:params:)``.
///
/// All cases carry ``BonjourServiceInfo`` rather than Apple-specific `NWEndpoint`,
/// so the type is safe to reference from any platform.
///
/// ```swift
/// for await result in bonjourBrowserStream(serviceType: "_myapp._tcp.") {
///     switch result {
///     case .success(.found(let info)):
///         print("found:", info.name, "txt:", info.txt ?? [:])
///     case .success(.removed(let info)):
///         print("lost:", info.name)
///     case .success(.updated(let old, let new)):
///         print("updated:", old.name, "→", new.name)
///     case .failure(let err):
///         print("browse error:", err)
///     }
/// }
/// ```
public enum BonjourBrowseEvent: Sendable {
    /// A service matching the search descriptor appeared on the network.
    case found(BonjourServiceInfo)
    /// A previously discovered service is no longer available.
    case removed(BonjourServiceInfo)
    /// A previously discovered service changed (e.g. appeared on a new interface).
    case updated(from: BonjourServiceInfo, to: BonjourServiceInfo)
}

/// Errors emitted by ``bonjourBrowserStream(serviceType:domain:params:)``.
public enum BonjourBrowseError: Error {
    /// The user has not granted local-network access to the app.
    case permissionDenied
    /// The browser failed with an underlying error.
    case didNotSearch(error: Error)
}
// swiftlint:enable discouraged_optional_collection
