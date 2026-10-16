// SPDX-License-Identifier: Apache-2.0

#if canImport(NIOCore)
import Core
import Foundation
import FP
import ReactiveConcurrency
import ReactiveConcurrencyTransformers

public struct Router<Env: Sendable>: @unchecked Sendable {
    public let pipeline: RoutePipeline<Env>

    public init(_ pipeline: @escaping RoutePipeline<Env>) {
        self.pipeline = pipeline
    }

    /// Runs the pipeline for one request, leaving the stack: read `Env`, then publish the response.
    public func handle(_ request: Request) -> Reader<Env, Publisher<Response, ResponseError>> {
        pipeline(request).rawValue
    }

    /// The empty router — always returns 404. Identity for `<|>`.
    public static var empty: Router<Env> {
        Router { _ in RouteEffect(Reader { _ in Publisher.fail(.notFound) }) }
    }

    public func contramap<World: Sendable>(_ f: @escaping @Sendable (World) -> Env) -> Router<World> {
        Router<World>({ [pipeline] request in
            pipeline(request).mapReaderT { $0.contramapEnvironment(f) }
        })
    }
}

// MARK: - Alternative

struct SendableHandler: @unchecked Sendable {
    let call: @Sendable (Request) -> Publisher<Response, ResponseError>
    func callAsFunction(_ request: Request) -> Publisher<Response, ResponseError> { call(request) }
}

public extension Router {
    /// Ordered choice: try `lhs`; fall through to `rhs` only on `.failure(.notFound)`.
    static func alt(_ lhs: Router<Env>, _ rhs: @autoclosure () -> Router<Env>) -> Router<Env> {
        let rhs = rhs()
        return Router { [lh = lhs.pipeline, rh = rhs.pipeline] request in
            RouteEffect(Reader { env in
                lh(request).rawValue(env).catch { error in
                    error.status == .notFound ? rh(request).rawValue(env) : Publisher.fail(error)
                }
            })
        }
    }
}

public func <|> <Env: Sendable>(_ lhs: Router<Env>, _ rhs: @autoclosure () -> Router<Env>) -> Router<Env> {
    Router.alt(lhs, rhs())
}
#endif
