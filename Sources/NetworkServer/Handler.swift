import Combine
import FP
import Foundation

/// A `FunctionWrapper` around `(Request) -> AnyPublisher<Response, Never>`.
///
/// Wrapping the handler type (rather than using a plain closure alias) enables
/// FunctionWrapper composition and lets callers build typed handler pipelines.
public struct Handler: FunctionWrapper<Request, AnyPublisher<Response, Never>>, @unchecked Sendable {
    public let run: (Request) -> AnyPublisher<Response, Never>

    public init(_ fn: @escaping (Request) -> AnyPublisher<Response, Never>) {
        run = fn
    }

    public func callAsFunction(_ request: Request) -> AnyPublisher<Response, Never> {
        run(request)
    }
}

/// A route matcher returns `nil` when neither the method nor the path pattern matches.
public typealias RouteMatcher = (Request) -> AnyPublisher<Response, Never>?
