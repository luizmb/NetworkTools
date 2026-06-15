// swiftlint:disable discouraged_optional_collection
#if canImport(Darwin)
import Foundation
import FP

/// Resolves a ``BonjourServiceInfo`` to its concrete host, port, and IP addresses.
///
/// Uses `NetService` internally — the only platform API that resolves a Bonjour
/// service name to IP addresses without opening a full connection. The public API
/// is clean and platform-agnostic; the `NetService` usage is an implementation detail.
///
/// - Parameters:
///   - service: The service to resolve, typically from a ``bonjourBrowserStream`` event.
///   - timeout: Maximum time (seconds) to wait for resolution. Defaults to 5 s.
/// - Returns: A lazy task that, when run, produces a ``ResolvedServiceInfo`` or an error.
///
/// ## Usage
///
/// ```swift
/// // Discover a service, resolve its address, then connect via WebSocket
/// for await result in bonjourBrowserStream(serviceType: "_myapp._tcp.") {
///     guard case .success(.found(let info)) = result else { continue }
///
///     switch await bonjourResolve(info, timeout: 5).run() {
///     case .success(let resolved):
///         print("host:", resolved.host ?? "?")
///         print("port:", resolved.port ?? 0)
///         print("IPs:", resolved.ips)
///         if let url = resolved.webSocketURL() {
///             let conn = await URLSession.shared.webSocketConnection(with: url).run()
///             _ = await conn.send(.text("hello")).run()
///         }
///     case .failure(let err):
///         print("resolve failed:", err)
///     }
/// }
/// ```
public func bonjourResolve(
    _ service: BonjourServiceInfo,
    timeout: TimeInterval = 5
) -> DeferredTask<Result<ResolvedServiceInfo, Error>> {
    DeferredTask {
        // Declared outside withCheckedContinuation so the async frame retains netService
        // across the suspension point.
        let netService = NetService(domain: service.domain, type: service.type, name: service.name)
        return await withCheckedContinuation { continuation in
            // Delegate retains itself (via strongSelf) until resolution or timeout fires.
            let delegate = NetServiceResolveDelegate(
                netService: netService,
                continuation: continuation
            )
            netService.delegate = delegate
            netService.resolve(withTimeout: timeout)
        }
    }
}

// MARK: - Error

/// Errors specific to ``bonjourResolve(_:timeout:)``.
public enum BonjourResolveError: Error {
    /// Resolution failed; `errorDict` contains `NSNetServicesErrorDomain` and
    /// `NSNetServicesErrorCode` keys matching `NSNetServicesError` constants.
    case didNotResolve(errorDict: [String: NSNumber])
}

// MARK: - Private delegate

private final class NetServiceResolveDelegate: NSObject, NetServiceDelegate, @unchecked Sendable {
    // Strong reference to netService prevents premature deallocation while the
    // async frame holds this delegate alive via strongSelf below.
    private let netService: NetService
    private var continuation: CheckedContinuation<Result<ResolvedServiceInfo, Error>, Never>?
    // Self-retention: breaks the cycle in complete(_:) once the result is delivered.
    private var strongSelf: NetServiceResolveDelegate?

    init(
        netService: NetService,
        continuation: CheckedContinuation<Result<ResolvedServiceInfo, Error>, Never>
    ) {
        self.netService = netService
        self.continuation = continuation
        super.init()
        strongSelf = self
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        let txt: [String: String]? = sender.txtRecordData()
            .map(NetService.dictionary(fromTXTRecord:))
            .map { $0.compactMapValues { String(data: $0, encoding: .utf8) } }
        complete(.success(ResolvedServiceInfo(
            name: sender.name,
            type: sender.type,
            domain: sender.domain,
            host: sender.hostName,
            port: UInt16(exactly: sender.port),
            ips: sender.parsedAddresses(),
            txt: txt
        )))
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        complete(.failure(BonjourResolveError.didNotResolve(errorDict: errorDict)))
    }

    private func complete(_ result: Result<ResolvedServiceInfo, Error>) {
        continuation?.resume(returning: result)
        continuation = nil
        strongSelf = nil
    }
}
#endif
// swiftlint:enable discouraged_optional_collection
