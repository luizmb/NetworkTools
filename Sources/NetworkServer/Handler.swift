import Core
import FP

// MARK: - Effect.response — NetworkServer entry points

public extension Effect {
    static func response<U, Q, B>(_ handler: @escaping @Sendable (Input, Environment) -> Result<Output, Failure>)
    -> Effect where Input == TypedRequest<U, Q, B>, Output == Response, Failure == ResponseError, Environment: Sendable {
        .init { req in Reader { env in DeferredTask { handler(req, env) } } }
    }

    static func response<U, Q, B>(_ handler: @escaping @Sendable (Input) -> Result<Output, Failure>)
    -> Effect where Input == TypedRequest<U, Q, B>, Output == Response, Failure == ResponseError, Environment: Sendable {
        .init { req in Reader { _ in DeferredTask { handler(req) } } }
    }

    static func response<U, Q, B>(_ handler: @escaping @Sendable (Input, Environment) -> DeferredTask<Result<Output, Failure>>)
    -> Effect where Input == TypedRequest<U, Q, B>, Output == Response, Failure == ResponseError, Environment: Sendable {
        .init { req in Reader { env in handler(req, env) } }
    }

    static func response<U, Q, B>(_ handler: @escaping @Sendable (Input) -> DeferredTask<Result<Output, Failure>>)
    -> Effect where Input == TypedRequest<U, Q, B>, Output == Response, Failure == ResponseError, Environment: Sendable {
        .init { req in Reader { _ in handler(req) } }
    }
}

#if canImport(Combine)
import Combine

public extension Effect {
    static func response<U, Q, B>(_ handler: @escaping @Sendable (Input, Environment) -> any Publisher<Output, Failure>)
    -> Effect where Input == TypedRequest<U, Q, B>, Output == Response, Failure == ResponseError, Environment: Sendable {
        .init { req in Reader { env in handler(req, env).eraseToAnyPublisher().asDeferredTask() } }
    }

    static func response<U, Q, B>(_ handler: @escaping @Sendable (Input) -> any Publisher<Output, Failure>)
    -> Effect where Input == TypedRequest<U, Q, B>, Output == Response, Failure == ResponseError, Environment: Sendable {
        .init { req in Reader { _ in handler(req).eraseToAnyPublisher().asDeferredTask() } }
    }
}
#endif
