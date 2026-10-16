// SPDX-License-Identifier: Apache-2.0

#if canImport(NIOCore)
import Core
import Foundation
import FP
import ReactiveConcurrency
import ReactiveConcurrencyTransformers

/// An ordered list of route pipelines. A request goes to the first route that answers with
/// anything other than `404`; `<|>` concatenates the lists, `empty` is the empty list.
public struct Router<Env: Sendable>: Sendable {
    private let routes: [RoutePipeline<Env>]

    public init(_ pipeline: @escaping RoutePipeline<Env>) {
        routes = [pipeline]
    }

    private init(routes: [RoutePipeline<Env>]) {
        self.routes = routes
    }

    /// The whole router as one pipeline step.
    public var pipeline: RoutePipeline<Env> {
        { [routes] request in RouteEffect(Reader { env in dispatch(routes, request, env) }) }
    }

    /// Runs the router for one request, leaving the stack: read `Env`, then publish the response.
    public func handle(_ request: Request) -> Reader<Env, Publisher<Response, ResponseError>> {
        Reader { [routes] env in dispatch(routes, request, env) }
    }

    /// The empty router — always returns 404. Identity for `<|>`.
    public static var empty: Router<Env> {
        Router(routes: [])
    }

    public func contramap<World: Sendable>(_ f: @escaping @Sendable (World) -> Env) -> Router<World> {
        Router<World>(routes: routes.map { route in
            { request in route(request).mapReaderT { $0.contramapEnvironment(f) } }
        })
    }
}

// One publisher tries the routes in order, so the cost of a request grows with the routes tried,
// not with how deeply `<|>` nested them. A route that finishes without a response ends the request
// with no response, as a `catch` chain would.
private func dispatch<Env: Sendable>(
    _ routes: [RoutePipeline<Env>],
    _ request: Request,
    _ env: Env
) -> Publisher<Response, ResponseError> {
    Publisher { continuation async throws(ResponseError) in
        for route in routes {
            switch await route(request).rawValue(env).firstResultTask().run() {
            case let .success(response)?:
                continuation.yield(response)
                return
            case let .failure(error)? where error.status == .notFound:
                continue
            case let .failure(error)?:
                continuation.fail(error)
                return
            case nil:
                return
            }
        }
        continuation.fail(.notFound)
    }
}

struct SendableHandler: @unchecked Sendable {
    let call: @Sendable (Request) -> Publisher<Response, ResponseError>
    func callAsFunction(_ request: Request) -> Publisher<Response, ResponseError> { call(request) }
}

// MARK: - Alternative

public extension Router {
    /// Ordered choice: try `lhs`; fall through to `rhs` only on `.failure(.notFound)`.
    static func alt(_ lhs: Router<Env>, _ rhs: @autoclosure () -> Router<Env>) -> Router<Env> {
        Router(routes: lhs.routes + rhs().routes)
    }
}

public func <|> <Env: Sendable>(_ lhs: Router<Env>, _ rhs: @autoclosure () -> Router<Env>) -> Router<Env> {
    Router.alt(lhs, rhs())
}
#endif
