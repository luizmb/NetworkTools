import Foundation
import FP

// MARK: - Env-independent lifters

public func handle<U, Q, B, Env: Sendable>(
    _ fn: @escaping @Sendable (TypedRequest<U, Q, B>) -> Response
) -> (TypedRequest<U, Q, B>) -> Reader<Env, DeferredTask<Result<Response, ResponseError>>> {
    { req in Reader { _ in DeferredTask { .success(fn(req)) } } }
}

public func handle<U, Q, B, Env: Sendable>(
    _ fn: @escaping @Sendable (TypedRequest<U, Q, B>) -> Result<Response, ResponseError>
) -> (TypedRequest<U, Q, B>) -> Reader<Env, DeferredTask<Result<Response, ResponseError>>> {
    { req in Reader { _ in DeferredTask { fn(req) } } }
}

public func handle<U, Q, B, Env: Sendable>(
    _ fn: @escaping @Sendable (TypedRequest<U, Q, B>) throws(ResponseError) -> Response
) -> (TypedRequest<U, Q, B>) -> Reader<Env, DeferredTask<Result<Response, ResponseError>>> {
    { req in
        Reader { _ in
            DeferredTask {
                do throws(ResponseError) { return .success(try fn(req)) } catch { return .failure(error) }
            }
        }
    }
}

public func handle<U, Q, B, Env: Sendable>(
    _ fn: @escaping @Sendable (TypedRequest<U, Q, B>) -> DeferredTask<Response>
) -> (TypedRequest<U, Q, B>) -> Reader<Env, DeferredTask<Result<Response, ResponseError>>> {
    { req in Reader { _ in DeferredTask { .success(await fn(req).run()) } } }
}

public func handle<U, Q, B, Env: Sendable>(
    _ fn: @escaping @Sendable (TypedRequest<U, Q, B>) -> DeferredTask<Result<Response, ResponseError>>
) -> (TypedRequest<U, Q, B>) -> Reader<Env, DeferredTask<Result<Response, ResponseError>>> {
    { req in Reader { _ in fn(req) } }
}

// MARK: - Env-dependent lifters

public func handle<U, Q, B, Env: Sendable>(
    _ fn: @escaping @Sendable (TypedRequest<U, Q, B>, Env) -> Response
) -> (TypedRequest<U, Q, B>) -> Reader<Env, DeferredTask<Result<Response, ResponseError>>> {
    { req in Reader { env in DeferredTask { .success(fn(req, env)) } } }
}

public func handle<U, Q, B, Env: Sendable>(
    _ fn: @escaping @Sendable (TypedRequest<U, Q, B>, Env) -> Result<Response, ResponseError>
) -> (TypedRequest<U, Q, B>) -> Reader<Env, DeferredTask<Result<Response, ResponseError>>> {
    { req in Reader { env in DeferredTask { fn(req, env) } } }
}

public func handle<U, Q, B, Env: Sendable>(
    _ fn: @escaping @Sendable (TypedRequest<U, Q, B>, Env) throws(ResponseError) -> Response
) -> (TypedRequest<U, Q, B>) -> Reader<Env, DeferredTask<Result<Response, ResponseError>>> {
    { req in
        Reader { env in
            DeferredTask {
                do throws(ResponseError) { return .success(try fn(req, env)) } catch { return .failure(error) }
            }
        }
    }
}

public func handle<U, Q, B, Env: Sendable>(
    _ fn: @escaping @Sendable (TypedRequest<U, Q, B>, Env) -> DeferredTask<Response>
) -> (TypedRequest<U, Q, B>) -> Reader<Env, DeferredTask<Result<Response, ResponseError>>> {
    { req in Reader { env in DeferredTask { .success(await fn(req, env).run()) } } }
}

public func handle<U, Q, B, Env: Sendable>(
    _ fn: @escaping @Sendable (TypedRequest<U, Q, B>, Env) -> DeferredTask<Result<Response, ResponseError>>
) -> (TypedRequest<U, Q, B>) -> Reader<Env, DeferredTask<Result<Response, ResponseError>>> {
    { req in Reader { env in fn(req, env) } }
}

// MARK: - Combine lifters

#if canImport(Combine)
import Combine

public func handle<U, Q, B, Env: Sendable>(
    _ fn: @escaping @Sendable (TypedRequest<U, Q, B>) -> AnyPublisher<Response, ResponseError>
) -> (TypedRequest<U, Q, B>) -> Reader<Env, DeferredTask<Result<Response, ResponseError>>> {
    { req in Reader { _ in fn(req).asDeferredTask() } }
}

public func handle<U, Q, B, Env: Sendable>(
    _ fn: @escaping @Sendable (TypedRequest<U, Q, B>, Env) -> AnyPublisher<Response, ResponseError>
) -> (TypedRequest<U, Q, B>) -> Reader<Env, DeferredTask<Result<Response, ResponseError>>> {
    { req in Reader { env in fn(req, env).asDeferredTask() } }
}
#endif
