// nil TXT (no record) is semantically distinct from [:] (empty record).
// swiftlint:disable discouraged_optional_collection
#if canImport(Combine)
import Combine
import Core
import Foundation
import Network

extension NWEndpoint {
    /// Resolves this endpoint to a `ResolvedEndpoint`, using a default `NetServicePublisher`
    /// for `.service` endpoints.
    public func publisher() -> NWEndpointPublisher {
        publisher { description, strategy in
            NetService(domain: description.domain, type: description.type, name: description.serviceName)
                .publisher(monitorDevice: strategy)
        }
    }

    /// Resolves this endpoint to a `ResolvedEndpoint`, injecting a custom NetService publisher.
    ///
    /// Useful when you want to control timeout, monitoring strategy, or substitute a mock
    /// in tests.
    public func publisher<P: Publisher>(
        netServicePublisher: @escaping (ServiceDescription, NetServiceTXTRecordsMonitorStrategy) -> P
    ) -> NWEndpointPublisher
    where P.Output == NetServicePublisher.Output, P.Failure == NetServicePublisher.Failure {
        .init(endpoint: self, netServicePublisher: netServicePublisher)
    }
}

/// A Combine `Publisher` that resolves an `NWEndpoint` to a concrete address and port.
///
/// For `.hostPort`, `.unix`, and `.url` endpoints the resolution is synchronous and the
/// publisher completes immediately after emitting one value. For `.service` endpoints a
/// `NetServicePublisher` is used to perform DNS resolution.
///
/// ## Resolving a host/port endpoint
///
/// ```swift
/// NWEndpoint.hostPort(host: "api.example.com", port: 443)
///     .publisher()
///     .sink(
///         receiveCompletion: { _ in },
///         receiveValue: { resolved in
///             print("host:", resolved.hostname ?? "?")
///             print("port:", resolved.port ?? 0)
///         }
///     )
///     .store(in: &cancellables)
/// ```
///
/// ## Resolving a Bonjour service endpoint
///
/// ```swift
/// NWEndpoint.service(name: "My Server", type: "_http._tcp.", domain: "local.", interface: nil)
///     .publisher()
///     .sink(
///         receiveCompletion: { _ in },
///         receiveValue: { resolved in
///             if case .service(let ns, _, _) = resolved {
///                 print("IPs:", ns.parsedAddresses())
///             }
///         }
///     )
///     .store(in: &cancellables)
/// ```
public struct NWEndpointPublisher {
    private let endpoint: NWEndpoint
    private let publishResolvedAddresses: Bool
    private let publishResolvedTXT: Bool
    private let netServicePublisherFactory: (ServiceDescription, NetServiceTXTRecordsMonitorStrategy)
        -> AnyPublisher<NetServicePublisher.Output, NetServicePublisher.Failure>

    public init<P: Publisher>(
        endpoint: NWEndpoint,
        netServicePublisher: @escaping (ServiceDescription, NetServiceTXTRecordsMonitorStrategy) -> P,
        publishResolvedAddresses: Bool = true,
        publishResolvedTXT: Bool = false
    ) where P.Output == NetServicePublisher.Output, P.Failure == NetServicePublisher.Failure {
        self.endpoint = endpoint
        self.netServicePublisherFactory = { netServicePublisher($0, $1).eraseToAnyPublisher() }
        self.publishResolvedAddresses = publishResolvedAddresses
        self.publishResolvedTXT = publishResolvedTXT
    }
}

extension NWEndpointPublisher: Publisher {
    public typealias Output = ResolvedEndpoint
    public typealias Failure = NWEndpointError

    public func receive<S>(subscriber: S)
    where S: Subscriber, Failure == S.Failure, Output == S.Input {
        switch endpoint {
        case .hostPort, .unix, .url:
            Just(.from(endpoint: endpoint, service: nil))
                .setFailureType(to: Failure.self)
                .subscribe(subscriber)

        case let .service(name, type, domain, interface):
            netServicePublisherFactory(
                ServiceDescription(serviceName: name, type: type, domain: domain),
                publishResolvedTXT ? .keepMonitoringTXTUpdates : .doNotMonitorTXTUpdates
            )
            .compactMap { event -> ResolvedEndpoint? in
                switch event.type {
                case .willPublish, .willResolve, .didPublish, .didAcceptConnectionWith:
                    return nil
                case .didResolveAddress:
                    guard publishResolvedAddresses else { return nil }
                    let txt = event.netService.txtRecordData().map(NetService.dictionary(fromTXTRecord:))
                    return .service(event.netService, interface: interface, txt: txt)
                case let .didUpdateTXTRecord(record):
                    guard publishResolvedTXT else { return nil }
                    event.netService.setTXTRecord(NetService.data(fromTXTRecord: record))
                    return .service(event.netService, interface: interface, txt: record)
                }
            }
            .mapError(Failure.netServiceError)
            .subscribe(subscriber)

        @unknown default:
            Fail(error: .endpointIsNotSupported).subscribe(subscriber)
        }
    }
}

// MARK: - Model

extension NWEndpointPublisher {
    public enum ResolvedEndpoint: Equatable {
        public enum HostType: Equatable {
            case name(String)
            case ip(IP)
        }

        case hostPort(host: HostType, port: Int, interface: NWInterface?, txt: [String: Data]?)
        case service(NetService, interface: NWInterface?, txt: [String: Data]?)
        case unix(path: String, txt: [String: Data]?)
        case url(URL, txt: [String: Data]?)
    }

    public enum NWEndpointError: Error {
        case endpointIsNotSupported
        case netServiceError(NetServicePublisher.Failure)
    }
}

extension NWEndpointPublisher.ResolvedEndpoint {
    public static func from(endpoint: NWEndpoint, service: NetService?) -> Self {
        let txt = service?.txtRecordData().map { NetService.dictionary(fromTXTRecord: $0) }
        switch endpoint {
        case let .hostPort(host, port):
            let portInt = Int(port.rawValue)
            switch host {
            case let .name(name, interface):
                return .hostPort(host: .name(name), port: portInt, interface: interface, txt: txt)
            case let .ipv4(v4):
                return .hostPort(host: .ip(IP.ipv4(v4)), port: portInt, interface: nil, txt: txt)
            case let .ipv6(v6):
                return .hostPort(host: .ip(IP.ipv6(v6)), port: portInt, interface: nil, txt: txt)
            @unknown default:
                fatalError("NWEndpoint.Host case not implemented: \(host)")
            }
        case let .service(name, type, domain, interface):
            return .service(service ?? NetService(domain: domain, type: type, name: name),
                            interface: interface, txt: txt)
        case let .unix(path):
            return .unix(path: path, txt: txt)
        case let .url(url):
            return .url(url, txt: txt)
        @unknown default:
            fatalError("NWEndpoint case not implemented: \(endpoint)")
        }
    }

    public var interface: NWInterface? {
        switch self {
        case let .hostPort(_, _, i, _): i
        case let .service(_, i, _):     i
        case .unix, .url:               nil
        }
    }

    public var txt: [String: Data]? {
        switch self {
        case let .hostPort(_, _, _, t): t
        case let .service(_, _, t):     t
        case let .unix(_, t):           t
        case let .url(_, t):            t
        }
    }

    public var hostname: String? {
        switch self {
        case let .hostPort(.name(h), _, _, _): h
        case let .service(s, _, _):            s.hostName
        case let .url(u, _):                   u.host
        case let .hostPort(.ip(ip), _, _, _):  ip.ipString
        case .unix:                            nil
        }
    }

    public var ips: [String]? {
        switch self {
        case let .hostPort(.ip(ip), _, _, _): [ip.ipString]
        case let .service(s, _, _):           s.parsedAddresses()
        case .hostPort(.name, _, _, _), .unix, .url: nil
        }
    }

    public var port: Int? {
        switch self {
        case let .hostPort(_, p, _, _): p
        case let .service(s, _, _):     s.port
        case let .url(u, _):            u.port
        case .unix:                     nil
        }
    }
}
#endif
// swiftlint:enable discouraged_optional_collection
