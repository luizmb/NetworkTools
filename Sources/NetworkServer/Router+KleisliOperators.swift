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

// public func >=> <Env: Sendable, A, B, C, E: Error>(
//     _ fn1: @escaping (A) -> Reader<Env, Result<B, E>>,
//     _ fn2: @escaping (B) -> Reader<Env, DeferredTask<Result<C, E>>>
// ) -> (A) -> Reader<Env, DeferredTask<Result<C, E>>> {
//     { a in
//         Reader { env in
//             switch fn1(a).runReader(env) {
//             case .failure(let e): DeferredTask { .failure(e) }
//             case .success(let b): fn2(b).runReader(env)
//             }
//         }
//     }
// }

// public func >=> <Env: Sendable, A, B, C, E: Error>(
//     _ fn1: @escaping (A) -> Reader<Env, Result<B, E>>,
//     _ fn2: Effect<B, Env, C, E>
// ) -> Effect<A, Env, C, E> {
//     .init { a in
//         Reader { env in
//             switch fn1(a).runReader(env) {
//             case .failure(let e): DeferredTask { Result<C, E>.failure(e) }
//             case .success(let b): fn2.run(b).runReader(env)
//             }
//         }
//     }
// }

// MARK: - HTTP verb entry points

public func receive<U: Decodable, Q: Decodable, Env: HasDictionaryDecoderFactory & Sendable>(
    _ method: HTTPMethod,
    _ path: String,
    params: U.Type = Empty.self,
    query: Q.Type = Empty.self
) -> Effect<Request, Env, MatchedRoute<U, Q>, ResponseError> {
    .init { request in 
        Route<U, Q>(method, path).match(request)
            .contramapEnvironment(\.dictionaryDecoderFactory)
            .map(DeferredTask.pure)
    }
}

public func get<U: Decodable, Q: Decodable, Env: HasDictionaryDecoderFactory & Sendable>(
    _ path: String,
    params: U.Type = Empty.self,
    query: Q.Type = Empty.self
) -> Effect<Request, Env, MatchedRoute<U, Q>, ResponseError> {
    receive(.GET, path, params: params, query: query)
}

public func post<U: Decodable, Q: Decodable, Env: HasDictionaryDecoderFactory & Sendable>(
    _ path: String,
    params: U.Type = Empty.self,
    query: Q.Type = Empty.self
) -> Effect<Request, Env, MatchedRoute<U, Q>, ResponseError> {
    receive(.POST, path, params: params, query: query)
}

public func put<U: Decodable, Q: Decodable, Env: HasDictionaryDecoderFactory & Sendable>(
    _ path: String,
    params: U.Type = Empty.self,
    query: Q.Type = Empty.self
) -> Effect<Request, Env, MatchedRoute<U, Q>, ResponseError> {
    receive(.PUT, path, params: params, query: query)
}

public func patch<U: Decodable, Q: Decodable, Env: HasDictionaryDecoderFactory & Sendable>(
    _ path: String,
    params: U.Type = Empty.self,
    query: Q.Type = Empty.self
) -> Effect<Request, Env, MatchedRoute<U, Q>, ResponseError> {
    receive(.PATCH, path, params: params, query: query)
}

public func delete<U: Decodable, Q: Decodable, Env: HasDictionaryDecoderFactory & Sendable>(
    _ path: String,
    params: U.Type = Empty.self,
    query: Q.Type = Empty.self
) -> Effect<Request, Env, MatchedRoute<U, Q>, ResponseError> {
    receive(.DELETE, path, params: params, query: query)
}

public func head<U: Decodable, Q: Decodable, Env: HasDictionaryDecoderFactory & Sendable>(
    _ path: String,
    params: U.Type = Empty.self,
    query: Q.Type = Empty.self
) -> Effect<Request, Env, MatchedRoute<U, Q>, ResponseError> {
    receive(.HEAD, path, params: params, query: query)
}

public func options<U: Decodable, Q: Decodable, Env: HasDictionaryDecoderFactory & Sendable>(
    _ path: String,
    params: U.Type = Empty.self,
    query: Q.Type = Empty.self
) -> Effect<Request, Env, MatchedRoute<U, Q>, ResponseError> {
    receive(.OPTIONS, path, params: params, query: query)
}

// MARK: - when — Router wrapper

/// Wraps a Kleisli chain into a `Router<DefaultEnv>`.
///
/// ```swift
/// when(get("/ping") >=> ignoreBody() >=> .response { _ in .html("pong") })
/// startServer(port: 8080, router: router).runReader(DefaultEnv())
/// ```
public func when(
    _ chain: Effect<Request, DefaultEnv, Response, ResponseError>
) -> Router<DefaultEnv> {
    Router(chain)
}

/// Wraps a Kleisli chain into a `Router<Env>`. Supply `injecting: Env.self` to pin the environment type.
///
/// ```swift
/// when(get("/albums/:id", params: AlbumID.self) >=> ignoreBody() >=> .response { req, env in
///     DeferredTask { … }
/// }, injecting: AppEnv.self)
/// ```
public func when<Env: Sendable>(
    _ chain: Effect<Request, Env, Response, ResponseError>,
    injecting _: Env.Type
) -> Router<Env> {
    Router(chain)
}

// MARK: - ignoreBody → Kleisli step

/// Passes a matched route through with an `Empty` body — no `Decodable` constraint imposed.
public func ignoreBody<U, Q, Env>() -> Effect<MatchedRoute<U, Q>, Env, TypedRequest<U, Q, Empty>, ResponseError> {
    .init { matched in
        Result<TypedRequest<U, Q, Empty>, ResponseError>.success(TypedRequest(urlParams: matched.urlParams, queryParams: matched.queryParams, body: .value, raw: matched.raw))
        |> DeferredTask.pure
        |> Reader.pure
    }
}

// MARK: - Body-decode → Kleisli step

/// Decodes the raw request body into `B` using a `DataDecoder<B>` extracted from the environment.
/// Maps decode failures to `400 Bad Request`.
///
/// Use a key-path lens to select the decoder explicitly — this makes the dependency visible at
/// the call site and lets different endpoints use different decoding strategies:
/// ```swift
/// >=> decodeBody(using: \.userDecoder)          // DataDecoder<User> stored on env
/// >=> decodeBody(using: \.jsonDecoder)           // JSONDecoder stored on env (factory overload)
/// ```
public func decodeBody<U, Q, B: Decodable & Sendable, Env>(using decoderLens: @escaping (Env) -> DataDecoder<B>) -> Effect<MatchedRoute<U, Q>, Env, TypedRequest<U, Q, B>, ResponseError> {
    .init { matched in
        Reader { env in
            let bodyData = matched.raw.body.isEmpty ? Data("{}".utf8) : matched.raw.body
            return decoderLens(env).run(bodyData)
                .map { body in
                    TypedRequest(
                        urlParams: matched.urlParams,
                        queryParams: matched.queryParams,
                        body: body,
                        raw: matched.raw
                    )
                }
                .mapError { ResponseError.badRequest($0.localizedDescription) }
                |> DeferredTask.pure
        }
    }
}

/// Convenience: selects a `DataDecoderFactory` from the environment and derives `DataDecoder<B>` from it.
public func decodeBody<U, Q, B: Decodable & Sendable, Env>(using decoderFactoryLens: @escaping (Env) -> DataDecoderFactory) -> Effect<MatchedRoute<U, Q>, Env, TypedRequest<U, Q, B>, ResponseError> {
    decodeBody(using: decoderFactoryLens >>> { $0.dataDecoder(for: B.self) })
}

/// Convenience: uses `env.dataDecoderFactory` when `Env: HasDataDecoderFactory`.
public func decodeBody<U, Q, B: Decodable & Sendable, Env: HasDataDecoderFactory>() -> Effect<MatchedRoute<U, Q>, Env, TypedRequest<U, Q, B>, ResponseError> {
    decodeBody(using: \.dataDecoderFactory)
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
