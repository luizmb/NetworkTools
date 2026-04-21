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

// MARK: - Route → Kleisli step

public extension Route {
    /// Lifts `match` into `Reader<Env, Result<…>>` for Kleisli composition via `>=>`.
    func matchReader<Env>() -> (Request) -> Reader<Env, Result<MatchedRoute<URLParams, QueryParams>, ResponseError>> {
        { request in Reader { _ in self.match(request) } }
    }
}

// MARK: - HTTP verb entry points

public func get<U: Decodable, Q: Decodable, Env>(
    _ path: String,
    params: U.Type = Empty.self,
    query: Q.Type = Empty.self
) -> (Request) -> Reader<Env, Result<MatchedRoute<U, Q>, ResponseError>> {
    Route<U, Q>(.GET, path).matchReader()
}

public func post<U: Decodable, Q: Decodable, Env>(
    _ path: String,
    params: U.Type = Empty.self,
    query: Q.Type = Empty.self
) -> (Request) -> Reader<Env, Result<MatchedRoute<U, Q>, ResponseError>> {
    Route<U, Q>(.POST, path).matchReader()
}

public func put<U: Decodable, Q: Decodable, Env>(
    _ path: String,
    params: U.Type = Empty.self,
    query: Q.Type = Empty.self
) -> (Request) -> Reader<Env, Result<MatchedRoute<U, Q>, ResponseError>> {
    Route<U, Q>(.PUT, path).matchReader()
}

public func patch<U: Decodable, Q: Decodable, Env>(
    _ path: String,
    params: U.Type = Empty.self,
    query: Q.Type = Empty.self
) -> (Request) -> Reader<Env, Result<MatchedRoute<U, Q>, ResponseError>> {
    Route<U, Q>(.PATCH, path).matchReader()
}

public func delete<U: Decodable, Q: Decodable, Env>(
    _ path: String,
    params: U.Type = Empty.self,
    query: Q.Type = Empty.self
) -> (Request) -> Reader<Env, Result<MatchedRoute<U, Q>, ResponseError>> {
    Route<U, Q>(.DELETE, path).matchReader()
}

public func head<U: Decodable, Q: Decodable, Env>(
    _ path: String,
    params: U.Type = Empty.self,
    query: Q.Type = Empty.self
) -> (Request) -> Reader<Env, Result<MatchedRoute<U, Q>, ResponseError>> {
    Route<U, Q>(.HEAD, path).matchReader()
}

public func options<U: Decodable, Q: Decodable, Env>(
    _ path: String,
    params: U.Type = Empty.self,
    query: Q.Type = Empty.self
) -> (Request) -> Reader<Env, Result<MatchedRoute<U, Q>, ResponseError>> {
    Route<U, Q>(.OPTIONS, path).matchReader()
}

// MARK: - when — Router wrapper

/// Wraps a Kleisli chain into a `Router<Void>`.
///
/// ```swift
/// when(get("/ping") >=> ignoreBody() >=> handle { _ in .html("pong") })
/// ```
public func when(
    _ chain: @escaping (Request) -> Reader<Void, DeferredTask<Result<Response, ResponseError>>>
) -> Router<Void> {
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
    _ decoder: DecoderResult<B>
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
}
