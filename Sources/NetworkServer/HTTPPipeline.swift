import Core
import Foundation
import FP
import NIOHTTP1

// MARK: - Core receive — explicit RouteParam injection

public func receive<U: Decodable & Sendable, Q: Decodable & Sendable, Env: Sendable>(
    _ method: HTTPMethod,
    _ path: String,
    params: RouteParam<U, Env>,
    query: RouteParam<Q, Env>
) -> RouteMatcher<U, Q, Env> {
    RouteMatcher { request in
        ZIO { env in
            DeferredTask {
                guard request.method == method,
                      let pathDict = matchPath(request.path, against: path)
                else { return .failure(.notFound) }

                guard case .success(let urlParams) = params.run(env, pathDict)
                else { return .failure(.notFound) }

                switch query.run(env, request.queryParams) {
                case .success(let queryParams):
                    return .success(MatchedRoute(urlParams: urlParams, queryParams: queryParams, raw: request))
                case .failure(let error):
                    return .failure(.badRequest(error.localizedDescription))
                }
            }
        }
    }
}

// MARK: - receive overloads

public func receive<Env: Sendable>(
    _ method: HTTPMethod,
    _ path: String
) -> RouteMatcher<Empty, Empty, Env> {
    receive(method, path, params: .ignore, query: .ignore)
}

public func receive<U: Decodable & Sendable, Env: Sendable>(
    _ method: HTTPMethod,
    _ path: String,
    params: RouteParam<U, Env>
) -> RouteMatcher<U, Empty, Env> {
    receive(method, path, params: params, query: .ignore)
}

public func receive<Q: Decodable & Sendable, Env: Sendable>(
    _ method: HTTPMethod,
    _ path: String,
    query: RouteParam<Q, Env>
) -> RouteMatcher<Empty, Q, Env> {
    receive(method, path, params: .ignore, query: query)
}

// MARK: - HTTP verb shortcuts

public func get<Env: Sendable>(_ path: String) -> RouteMatcher<Empty, Empty, Env> { receive(.GET, path) }
public func get<U: Decodable & Sendable, Env: Sendable>(_ path: String, params: RouteParam<U, Env>) -> RouteMatcher<U, Empty, Env> {
    receive(.GET, path, params: params)
}
public func get<Q: Decodable & Sendable, Env: Sendable>(_ path: String, query: RouteParam<Q, Env>) -> RouteMatcher<Empty, Q, Env> {
    receive(.GET, path, query: query)
}
public func get<U: Decodable & Sendable, Q: Decodable & Sendable, Env: Sendable>(
    _ path: String,
    params: RouteParam<U, Env>,
    query: RouteParam<Q, Env>
) -> RouteMatcher<U, Q, Env> {
    receive(.GET, path, params: params, query: query)
}

public func post<Env: Sendable>(_ path: String) -> RouteMatcher<Empty, Empty, Env> { receive(.POST, path) }
public func post<U: Decodable & Sendable, Env: Sendable>(_ path: String, params: RouteParam<U, Env>) -> RouteMatcher<U, Empty, Env> {
    receive(.POST, path, params: params)
}
public func post<Q: Decodable & Sendable, Env: Sendable>(_ path: String, query: RouteParam<Q, Env>) -> RouteMatcher<Empty, Q, Env> {
    receive(.POST, path, query: query)
}
public func post<U: Decodable & Sendable, Q: Decodable & Sendable, Env: Sendable>(
    _ path: String,
    params: RouteParam<U, Env>,
    query: RouteParam<Q, Env>
) -> RouteMatcher<U, Q, Env> {
    receive(.POST, path, params: params, query: query)
}

public func put<Env: Sendable>(_ path: String) -> RouteMatcher<Empty, Empty, Env> { receive(.PUT, path) }
public func put<U: Decodable & Sendable, Env: Sendable>(_ path: String, params: RouteParam<U, Env>) -> RouteMatcher<U, Empty, Env> {
    receive(.PUT, path, params: params)
}
public func put<Q: Decodable & Sendable, Env: Sendable>(_ path: String, query: RouteParam<Q, Env>) -> RouteMatcher<Empty, Q, Env> {
    receive(.PUT, path, query: query)
}
public func put<U: Decodable & Sendable, Q: Decodable & Sendable, Env: Sendable>(
    _ path: String,
    params: RouteParam<U, Env>,
    query: RouteParam<Q, Env>
) -> RouteMatcher<U, Q, Env> {
    receive(.PUT, path, params: params, query: query)
}

public func patch<Env: Sendable>(_ path: String) -> RouteMatcher<Empty, Empty, Env> { receive(.PATCH, path) }
public func patch<U: Decodable & Sendable, Env: Sendable>(_ path: String, params: RouteParam<U, Env>) -> RouteMatcher<U, Empty, Env> {
    receive(.PATCH, path, params: params)
}
public func patch<Q: Decodable & Sendable, Env: Sendable>(_ path: String, query: RouteParam<Q, Env>) -> RouteMatcher<Empty, Q, Env> {
    receive(.PATCH, path, query: query)
}
public func patch<U: Decodable & Sendable, Q: Decodable & Sendable, Env: Sendable>(
    _ path: String,
    params: RouteParam<U, Env>,
    query: RouteParam<Q, Env>
) -> RouteMatcher<U, Q, Env> {
    receive(.PATCH, path, params: params, query: query)
}

public func delete<Env: Sendable>(_ path: String) -> RouteMatcher<Empty, Empty, Env> { receive(.DELETE, path) }
public func delete<U: Decodable & Sendable, Env: Sendable>(_ path: String, params: RouteParam<U, Env>) -> RouteMatcher<U, Empty, Env> {
    receive(.DELETE, path, params: params)
}
public func delete<Q: Decodable & Sendable, Env: Sendable>(_ path: String, query: RouteParam<Q, Env>) -> RouteMatcher<Empty, Q, Env> {
    receive(.DELETE, path, query: query)
}
public func delete<U: Decodable & Sendable, Q: Decodable & Sendable, Env: Sendable>(
    _ path: String,
    params: RouteParam<U, Env>,
    query: RouteParam<Q, Env>
) -> RouteMatcher<U, Q, Env> {
    receive(.DELETE, path, params: params, query: query)
}

public func head<Env: Sendable>(_ path: String) -> RouteMatcher<Empty, Empty, Env> { receive(.HEAD, path) }
public func head<U: Decodable & Sendable, Env: Sendable>(_ path: String, params: RouteParam<U, Env>) -> RouteMatcher<U, Empty, Env> {
    receive(.HEAD, path, params: params)
}
public func head<Q: Decodable & Sendable, Env: Sendable>(_ path: String, query: RouteParam<Q, Env>) -> RouteMatcher<Empty, Q, Env> {
    receive(.HEAD, path, query: query)
}
public func head<U: Decodable & Sendable, Q: Decodable & Sendable, Env: Sendable>(
    _ path: String,
    params: RouteParam<U, Env>,
    query: RouteParam<Q, Env>
) -> RouteMatcher<U, Q, Env> {
    receive(.HEAD, path, params: params, query: query)
}

public func options<Env: Sendable>(_ path: String) -> RouteMatcher<Empty, Empty, Env> { receive(.OPTIONS, path) }
public func options<U: Decodable & Sendable, Env: Sendable>(_ path: String, params: RouteParam<U, Env>) -> RouteMatcher<U, Empty, Env> {
    receive(.OPTIONS, path, params: params)
}
public func options<Q: Decodable & Sendable, Env: Sendable>(_ path: String, query: RouteParam<Q, Env>) -> RouteMatcher<Empty, Q, Env> {
    receive(.OPTIONS, path, query: query)
}
public func options<U: Decodable & Sendable, Q: Decodable & Sendable, Env: Sendable>(
    _ path: String,
    params: RouteParam<U, Env>,
    query: RouteParam<Q, Env>
) -> RouteMatcher<U, Q, Env> {
    receive(.OPTIONS, path, params: params, query: query)
}

// MARK: - when — Router wrapper

/// Wraps a Kleisli chain into a `Router<Env>`.
///
/// ```swift
/// when(get("/ping") >=> ignoreBody() >=> .response { _ in .html("pong") }, injecting: Void.self)
/// startServer(port: 8080, router: router).runReader(())
/// ```
public func when<Env: Sendable>(
    _ chain: RoutePipeline<Env>,
    injecting _: Env.Type
) -> Router<Env> {
    Router(chain)
}

// MARK: - ignoreBody → BodyDecoder step

/// Passes a matched route through with an `Empty` body — no `Decodable` constraint imposed.
public func ignoreBody<U, Q, Env: Sendable>() -> BodyDecoder<U, Q, Empty, Env> {
    BodyDecoder { matched in
        .pure(TypedRequest(urlParams: matched.urlParams, queryParams: matched.queryParams, body: .value, raw: matched.raw))
    }
}

// MARK: - Body-decode → BodyDecoder step

/// Decodes the raw request body into `B` using a `DataDecoder<B>` extracted from the environment.
/// Maps decode failures to `400 Bad Request`.
///
/// Use a key-path lens to select the decoder explicitly:
/// ```swift
/// >=> decodeBody(using: \.userDecoder)   // DataDecoder<User> stored on env
/// >=> decodeBody(using: \.jsonDecoder)   // JSONDecoder stored on env (factory overload)
/// ```
public func decodeBody<U, Q, B: Decodable & Sendable, Env: Sendable>(
    using decoderLens: @escaping @Sendable (Env) -> DataDecoder<B>
) -> BodyDecoder<U, Q, B, Env> {
    BodyDecoder { matched in
        ZIO { env in
            let bodyData = matched.raw.body.isEmpty ? Data("{}".utf8) : matched.raw.body
            return DeferredTask {
                decoderLens(env).run(bodyData)
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
}

/// Convenience: selects a `DataDecoderFactory` from the environment and derives `DataDecoder<B>` from it.
public func decodeBody<U, Q, B: Decodable & Sendable, Env: Sendable>(
    using decoderFactoryLens: @escaping @Sendable (Env) -> DataDecoderFactory
) -> BodyDecoder<U, Q, B, Env> {
    decodeBody(using: { @Sendable env in decoderFactoryLens(env).dataDecoder(for: B.self) })
}

/// Convenience: uses `env.dataDecoderFactory` when `Env: HasDataDecoderFactory`.
public func decodeBody<U, Q, B: Decodable & Sendable, Env: HasDataDecoderFactory>() -> BodyDecoder<U, Q, B, Env> {
    decodeBody(using: \.dataDecoderFactory)
}
