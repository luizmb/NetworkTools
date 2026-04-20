import FP
import Foundation

public struct Handler<URLParams, QueryParams, Body, Env: Sendable>: @unchecked Sendable {
    let run: (TypedRequest<URLParams, QueryParams, Body>) -> Reader<Env, DeferredTask<Result<Response, ResponseError>>>

    public init(_ run: @escaping (TypedRequest<URLParams, QueryParams, Body>) -> Reader<Env, DeferredTask<Result<Response, ResponseError>>>) {
        self.run = run
    }
}

// MARK: - Env-independent

extension Handler {
    public static func handle(
        _ fn: @escaping @Sendable (TypedRequest<URLParams, QueryParams, Body>) -> Response
    ) -> Self {
        Self { req in Reader { _ in DeferredTask { .success(fn(req)) } } }
    }

    public static func handle(
        _ fn: @escaping @Sendable (TypedRequest<URLParams, QueryParams, Body>) -> Result<Response, ResponseError>
    ) -> Self {
        Self { req in Reader { _ in DeferredTask { fn(req) } } }
    }

    public static func handle(
        _ fn: @escaping @Sendable (TypedRequest<URLParams, QueryParams, Body>) throws(ResponseError) -> Response
    ) -> Self {
        Self { req in
            Reader { _ in
                DeferredTask {
                    do throws(ResponseError) { return .success(try fn(req)) } catch { return .failure(error) }
                }
            }
        }
    }

    public static func handle(
        _ fn: @escaping @Sendable (TypedRequest<URLParams, QueryParams, Body>) -> DeferredTask<Response>
    ) -> Self {
        Self { req in Reader { _ in DeferredTask { .success(await fn(req).run()) } } }
    }

    public static func handle(
        _ fn: @escaping @Sendable (TypedRequest<URLParams, QueryParams, Body>) -> DeferredTask<Result<Response, ResponseError>>
    ) -> Self {
        Self { req in Reader { _ in fn(req) } }
    }
}

// MARK: - Env-dependent

extension Handler {
    public static func handle(
        _ fn: @escaping @Sendable (TypedRequest<URLParams, QueryParams, Body>) -> Reader<Env, Response>
    ) -> Self {
        Self { req in Reader { env in DeferredTask { .success(fn(req).runReader(env)) } } }
    }

    public static func handle(
        _ fn: @escaping @Sendable (TypedRequest<URLParams, QueryParams, Body>) -> Reader<Env, Result<Response, ResponseError>>
    ) -> Self {
        Self { req in Reader { env in DeferredTask { fn(req).runReader(env) } } }
    }

    public static func handle(
        _ fn: @escaping @Sendable (TypedRequest<URLParams, QueryParams, Body>) -> Reader<Env, DeferredTask<Response>>
    ) -> Self {
        Self { req in Reader { env in DeferredTask { .success(await fn(req).runReader(env).run()) } } }
    }

    public static func handle(
        _ fn: @escaping @Sendable (TypedRequest<URLParams, QueryParams, Body>) -> Reader<Env, DeferredTask<Result<Response, ResponseError>>>
    ) -> Self {
        Self(fn)
    }
}

// MARK: - Combine

#if canImport(Combine)
import Combine

extension Handler {
    public static func handle(
        _ fn: @escaping @Sendable (TypedRequest<URLParams, QueryParams, Body>) -> AnyPublisher<Response, Never>
    ) -> Self {
        Self { req in Reader { _ in DeferredTask { .success(await fn(req).asDeferredTask().run()) } } }
    }

    public static func handle(
        _ fn: @escaping @Sendable (TypedRequest<URLParams, QueryParams, Body>) -> Reader<Env, AnyPublisher<Response, Never>>
    ) -> Self {
        Self { req in Reader { env in DeferredTask { .success(await fn(req).runReader(env).asDeferredTask().run()) } } }
    }
}
#endif
