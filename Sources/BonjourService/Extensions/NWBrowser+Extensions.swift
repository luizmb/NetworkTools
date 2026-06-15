#if canImport(Network)
import Foundation
import Network

// swiftlint:disable discouraged_optional_collection
extension NWBrowser.Result.Metadata {
    /// Extracts the Bonjour TXT record as a `[String: String]` dictionary.
    ///
    /// Returns `nil` when there is no TXT record (`.none` metadata), and an empty
    /// dictionary when the record exists but is empty. This distinction mirrors the
    /// underlying Bonjour TXT record semantics.
    ///
    /// ```swift
    /// browser.browseResultsChangedHandler = { _, changes in
    ///     for change in changes {
    ///         if case .added(let result) = change {
    ///             let txt = result.metadata.txt  // [String: String]?
    ///         }
    ///     }
    /// }
    /// ```
    public var txt: [String: String]? {
        switch self {
        case .none:
            return nil
        case let .bonjour(record):
            return record.dictionary
        @unknown default:
            return nil
        }
    }
}
// swiftlint:enable discouraged_optional_collection
#endif
