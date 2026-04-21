import Core
import Foundation
import FP

public struct Router<Env: Sendable>: @unchecked Sendable {
    /// The entire router as a `Reader`: inject the environment once at server startup,
    /// receive back a concrete `(Request) -> DeferredTask<…>` that never needs the env again.
    public let handle: Reader<Env, (Request) -> DeferredTask<Result<Response, ResponseError>>>

    public init(_ handle: Reader<Env, (Request) -> DeferredTask<Result<Response, ResponseError>>>) {
        self.handle = handle
    }

    /// The empty router — always returns 404. Identity for `<|>`.
    public static var empty: Router<Env> {
        Router(Reader { _ in { _ in DeferredTask { .failure(.notFound) } } })
    }

    public func pullback<World: Sendable>(_ f: @escaping (World) -> Env) -> Router<World> {
        Router<World>(handle.contramapEnvironment(f))
    }
}

// MARK: - Alternative

struct SendableHandler: @unchecked Sendable {
    let call: (Request) -> DeferredTask<Result<Response, ResponseError>>
    func callAsFunction(_ request: Request) -> DeferredTask<Result<Response, ResponseError>> { call(request) }
}

extension Router {
    /// Ordered choice: try `lhs`; fall through to `rhs` only on `.failure(.notFound)`.
    /// Both sub-routers are materialised once inside the Reader — at server-start time, not per request.
    public static func alt(_ lhs: Router<Env>, _ rhs: @autoclosure () -> Router<Env>) -> Router<Env> {
        let rhs = rhs()
        return Router(Reader { env in
            let l = SendableHandler(call: lhs.handle.runReader(env))
            let r = SendableHandler(call: rhs.handle.runReader(env))
            return { request in
                DeferredTask {
                    let result = await l(request).run()
                    if case .failure(let e) = result, e.status == .notFound {
                        return await r(request).run()
                    }
                    return result
                }
            }
        })
    }
}

public func <|> <Env: Sendable>(_ lhs: Router<Env>, _ rhs: @autoclosure () -> Router<Env>) -> Router<Env> {
    Router.alt(lhs, rhs())
}
