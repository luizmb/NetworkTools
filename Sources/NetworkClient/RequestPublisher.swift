#if canImport(Combine)
import Combine
import Foundation
import FP

/// A `FunctionWrapper` around `(URLRequest) -> AnyPublisher<A, HTTPError>`.
///
/// Combines the Reader monad (threading the same `URLRequest` through a chain)
/// with the Publisher monad (async response streaming with typed errors).
public struct RequestPublisher<A>: FunctionWrapper {
    public let run: (URLRequest) -> AnyPublisher<A, HTTPError>

    public init(_ fn: @escaping (URLRequest) -> AnyPublisher<A, HTTPError>) {
        run = fn
    }

    public func callAsFunction(_ request: URLRequest) -> AnyPublisher<A, HTTPError> {
        run(request)
    }
}

/// `RequestPublisher` specialised to the raw HTTP response pair.
public typealias Requester = RequestPublisher<(Data, HTTPURLResponse)>
#endif
