import Core
import FP

// MARK: - Domain typealiases for the HTTP routing pipeline

/// A step in the HTTP request-processing pipeline.
public typealias RouteStep<I: Sendable, Env: Sendable, O: Sendable> = ZIOKleisli<I, Env, O, ResponseError>

/// Route matching step: dispatches a raw `Request` to a `MatchedRoute<U, Q>`.
public typealias RouteMatcher<U: Sendable, Q: Sendable, Env: Sendable> = RouteStep<Request, Env, MatchedRoute<U, Q>>

/// Body decoding step: promotes a `MatchedRoute` to a fully typed `TypedRequest<U, Q, B>`.
public typealias BodyDecoder<U: Sendable, Q: Sendable, B: Sendable, Env: Sendable> = RouteStep<MatchedRoute<U, Q>, Env, TypedRequest<U, Q, B>>

/// Terminal handler: produces a `Response` from a fully typed `TypedRequest<U, Q, B>`.
public typealias ResponseHandler<U: Sendable, Q: Sendable, B: Sendable, Env: Sendable> = RouteStep<TypedRequest<U, Q, B>, Env, Response>

/// Full pipeline: maps a `Request` directly to a `Response` within `Env`.
public typealias RoutePipeline<Env: Sendable> = RouteStep<Request, Env, Response>

// MARK: - ZIOKleisli.response — NetworkServer entry points

public extension ZIOKleisli {
    static func response<U, Q, B>(_ handler: @escaping @Sendable (Input, Env) -> Result<Success, Failure>)
    -> ZIOKleisli where Input == TypedRequest<U, Q, B>, Success == Response, Failure == ResponseError, Env: Sendable {
        ZIOKleisli { req in ZIO { env in DeferredTask { handler(req, env) } } }
    }

    static func response<U, Q, B>(_ handler: @escaping @Sendable (Input) -> Result<Success, Failure>)
    -> ZIOKleisli where Input == TypedRequest<U, Q, B>, Success == Response, Failure == ResponseError, Env: Sendable {
        ZIOKleisli { req in ZIO { _ in DeferredTask { handler(req) } } }
    }

    static func response<U, Q, B>(_ handler: @escaping @Sendable (Input, Env) -> DeferredTask<Result<Success, Failure>>)
    -> ZIOKleisli where Input == TypedRequest<U, Q, B>, Success == Response, Failure == ResponseError, Env: Sendable {
        ZIOKleisli { req in ZIO { env in handler(req, env) } }
    }

    static func response<U, Q, B>(_ handler: @escaping @Sendable (Input) -> DeferredTask<Result<Success, Failure>>)
    -> ZIOKleisli where Input == TypedRequest<U, Q, B>, Success == Response, Failure == ResponseError, Env: Sendable {
        ZIOKleisli { req in ZIO { _ in handler(req) } }
    }
}

#if canImport(Combine)
import Combine

public extension ZIOKleisli {
    static func response<U, Q, B>(_ handler: @escaping @Sendable (Input, Env) -> any Publisher<Success, Failure>)
    -> ZIOKleisli where Input == TypedRequest<U, Q, B>, Success == Response, Failure == ResponseError, Env: Sendable {
        ZIOKleisli { req in ZIO { env in handler(req, env).eraseToAnyPublisher().asDeferredTask() } }
    }

    static func response<U, Q, B>(_ handler: @escaping @Sendable (Input) -> any Publisher<Success, Failure>)
    -> ZIOKleisli where Input == TypedRequest<U, Q, B>, Success == Response, Failure == ResponseError, Env: Sendable {
        ZIOKleisli { req in ZIO { _ in handler(req).eraseToAnyPublisher().asDeferredTask() } }
    }
}
#endif
