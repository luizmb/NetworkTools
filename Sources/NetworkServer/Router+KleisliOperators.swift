import Core
import Foundation
import FP
import NIOHTTP1

// MARK: - Bridge: (A -> Reader<Env, Result<B, E>>) >=> (B -> Reader<Env, DeferredTask<Result<C, E>>>)
//
// FP already provides:
//   >=>  for ReaderTResult  (both legs produce Reader<Env, Result<…>>)
//   >=>  for ReaderTDeferredTask (both legs produce Reader<Env, DeferredTask<…>>)
//
// This overload bridges the two: the sync routing/decoding phase (ReaderTResult)
// into the async handler phase (ReaderTDeferredTaskResult).

public func >=> <Env: Sendable, A, B, C, E: Error>(
    _ fn1: @escaping (A) -> Reader<Env, Result<B, E>>,
    _ fn2: @escaping (B) -> Reader<Env, DeferredTask<Result<C, E>>>
) -> (A) -> Reader<Env, DeferredTask<Result<C, E>>> {
    { a in
        Reader { env in
            switch fn1(a).runReader(env) {
            case .failure(let e): DeferredTask { .failure(e) }
            case .success(let b): fn2(b).runReader(env)
            }
        }
    }
}

public func >=> <Env: Sendable, A, B, C, E: Error>(
    _ fn1: @escaping (A) -> Reader<Env, Result<B, E>>,
    _ fn2: Effect<B, Env, C, E>
) -> Effect<A, Env, C, E> {
    .init { a in
        Reader { env in
            switch fn1(a).runReader(env) {
            case .failure(let e): DeferredTask { Result<C, E>.failure(e) }
            case .success(let b): fn2.run(b).runReader(env)
            }
        }
    }
}

// MARK: - HTTP verb entry points

public func get<U: Decodable, Q: Decodable, Env: HasDictionaryDecoderFactory>(
    _ path: String,
    params: U.Type = Empty.self,
    query: Q.Type = Empty.self
) -> (Request) -> Reader<Env, Result<MatchedRoute<U, Q>, ResponseError>> {
    { request in
        Route<U, Q>(.GET, path).match(request).contramapEnvironment(\.dictionaryDecoderFactory)
    }
}

public func post<U: Decodable, Q: Decodable, Env: HasDictionaryDecoderFactory>(
    _ path: String,
    params: U.Type = Empty.self,
    query: Q.Type = Empty.self
) -> (Request) -> Reader<Env, Result<MatchedRoute<U, Q>, ResponseError>> {
    { request in
        Route<U, Q>(.POST, path).match(request).contramapEnvironment(\.dictionaryDecoderFactory)
    }
}

public func put<U: Decodable, Q: Decodable, Env: HasDictionaryDecoderFactory>(
    _ path: String,
    params: U.Type = Empty.self,
    query: Q.Type = Empty.self
) -> (Request) -> Reader<Env, Result<MatchedRoute<U, Q>, ResponseError>> {
    { request in
        Route<U, Q>(.PUT, path).match(request).contramapEnvironment(\.dictionaryDecoderFactory)
    }
}

public func patch<U: Decodable, Q: Decodable, Env: HasDictionaryDecoderFactory>(
    _ path: String,
    params: U.Type = Empty.self,
    query: Q.Type = Empty.self
) -> (Request) -> Reader<Env, Result<MatchedRoute<U, Q>, ResponseError>> {
    { request in
        Route<U, Q>(.PATCH, path).match(request).contramapEnvironment(\.dictionaryDecoderFactory)
    }
}

public func delete<U: Decodable, Q: Decodable, Env: HasDictionaryDecoderFactory>(
    _ path: String,
    params: U.Type = Empty.self,
    query: Q.Type = Empty.self
) -> (Request) -> Reader<Env, Result<MatchedRoute<U, Q>, ResponseError>> {
    { request in
        Route<U, Q>(.DELETE, path).match(request).contramapEnvironment(\.dictionaryDecoderFactory)
    }
}

public func head<U: Decodable, Q: Decodable, Env: HasDictionaryDecoderFactory>(
    _ path: String,
    params: U.Type = Empty.self,
    query: Q.Type = Empty.self
) -> (Request) -> Reader<Env, Result<MatchedRoute<U, Q>, ResponseError>> {
    { request in
        Route<U, Q>(.HEAD, path).match(request).contramapEnvironment(\.dictionaryDecoderFactory)
    }
}

public func options<U: Decodable, Q: Decodable, Env: HasDictionaryDecoderFactory>(
    _ path: String,
    params: U.Type = Empty.self,
    query: Q.Type = Empty.self
) -> (Request) -> Reader<Env, Result<MatchedRoute<U, Q>, ResponseError>> {
    { request in
        Route<U, Q>(.OPTIONS, path).match(request).contramapEnvironment(\.dictionaryDecoderFactory)
    }
}

// MARK: - when — Router wrapper

/// Wraps a Kleisli chain into a `Router<DefaultEnv>`.
///
/// ```swift
/// when(get("/ping") >=> ignoreBody() >=> handle { _ in .html("pong") })
/// startServer(port: 8080, router: router).runReader(DefaultEnv())
/// ```
public func when(
    _ chain: @escaping (Request) -> Reader<DefaultEnv, DeferredTask<Result<Response, ResponseError>>>
) -> Router<DefaultEnv> {
    Router(chain)
}

/// Wraps a Kleisli chain into a `Router<Env>`. Supply `injecting: Env.self` to pin the environment type.
///
/// ```swift
/// when(get("/albums/:id", params: AlbumID.self) >=> ignoreBody() >=> handle { req in
///     Reader { env in … }
/// }, injecting: AppEnv.self)
/// ```
public func when<Env: Sendable>(
    _ chain: @escaping (Request) -> Reader<Env, DeferredTask<Result<Response, ResponseError>>>,
    injecting _: Env.Type
) -> Router<Env> {
    Router(chain)
}

/// Wraps an `Effect`-based Kleisli chain into a `Router<DefaultEnv>`.
///
/// ```swift
/// when(get("/ping") >=> ignoreBody() >=> Effect.response { _ in .html("pong") })
/// ```
public func when(_ effect: Effect<Request, DefaultEnv, Response, ResponseError>) -> Router<DefaultEnv> {
    Router(effect)
}

/// Wraps an `Effect`-based Kleisli chain into a `Router<Env>`.
///
/// ```swift
/// when(get("/albums/:id", params: AlbumID.self) >=> ignoreBody() >=> Effect.response { req, env in … },
///      injecting: AppEnv.self)
/// ```
public func when<Env: Sendable>(
    _ effect: Effect<Request, Env, Response, ResponseError>,
    injecting _: Env.Type
) -> Router<Env> {
    Router(effect)
}

// MARK: - ignoreBody → Kleisli step

/// Passes a matched route through with an `Empty` body — no `Decodable` constraint imposed.
public func ignoreBody<U, Q, Env>() -> (MatchedRoute<U, Q>) -> Reader<Env, Result<TypedRequest<U, Q, Empty>, ResponseError>> {
    { matched in
        Reader { _ in
            .success(TypedRequest(urlParams: matched.urlParams, queryParams: matched.queryParams, body: .value, raw: matched.raw))
        }
    }
}

// MARK: - Body-decode → Kleisli step

/// Lifts a `DecoderResult<B>` into `Reader<Env, Result<…>>` for Kleisli composition via `>=>`.
/// Applies the decoder to the raw request body; maps decode failures to `400 Bad Request`.
public func decodeBody<U, Q, B: Decodable, Env>(
    _ decoder: DataDecoder<B>
) -> (MatchedRoute<U, Q>) -> Reader<Env, Result<TypedRequest<U, Q, B>, ResponseError>> {
    { matched in
        Reader { _ in
            let bodyData = matched.raw.body.isEmpty ? Data("{}".utf8) : matched.raw.body
            return decoder.run(bodyData)
                .map { body in
                    TypedRequest(
                        urlParams: matched.urlParams,
                        queryParams: matched.queryParams,
                        body: body,
                        raw: matched.raw
                    )
                }
                .mapError { ResponseError.badRequest($0.localizedDescription) }
        }
    }
}

// MARK: - Router init from Kleisli chain

extension Router {
    init(_ fn: @escaping (Request) -> Reader<Env, DeferredTask<Result<Response, ResponseError>>>) {
        self.init(Reader { env in { request in fn(request).runReader(env) } })
    }

    init(_ effect: Effect<Request, Env, Response, ResponseError>) {
        self.init(Reader { env in { request in effect.run(request).runReader(env) } })
    }
}
