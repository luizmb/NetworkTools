// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin)
import Foundation

public extension NetService {
    /// Resolves the raw socket-address data into human-readable IP address strings.
    ///
    /// Uses `getnameinfo` with `NI_NUMERICHOST` to convert each `sockaddr` in `addresses`
    /// to its numeric IP string without DNS lookup. Returns an empty array if the service
    /// has not yet been resolved.
    ///
    /// ```swift
    /// let publisher = NetService(domain: "local.", type: "_http._tcp.", name: "My Server")
    ///     .publisher(monitorDevice: .doNotMonitorTXTUpdates)
    ///
    /// publisher
    ///     .compactMap { event -> [String]? in
    ///         guard case .didResolveAddress = event.type else { return nil }
    ///         return event.netService.parsedAddresses()
    ///     }
    ///     .sink { ips in print("resolved IPs:", ips) }
    ///     .store(in: &cancellables)
    /// ```
    func parsedAddresses() -> [String] {
        guard let addresses else { return [] }
        return addresses.compactMap { addressData in
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            addressData.withUnsafeBytes { ptr in
                guard let base = ptr.baseAddress?.assumingMemoryBound(to: sockaddr.self) else { return }
                getnameinfo(
                    base,
                    socklen_t(base.pointee.sa_len),
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )
            }
            return String(cString: hostname)
        }
    }
}
#endif
