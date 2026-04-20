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

    public init() {
        handle = Reader { _ in { _ in DeferredTask { .failure(.notFound) } } }
    }

    public func pullback<World: Sendable>(_ f: @escaping (World) -> Env) -> Router<World> {
        Router<World>(handle.contramapEnvironment(f))
    }
}

// MARK: - Semigroup / Monoid

struct SendableHandler: @unchecked Sendable {
    let call: (Request) -> DeferredTask<Result<Response, ResponseError>>
    func callAsFunction(_ request: Request) -> DeferredTask<Result<Response, ResponseError>> { call(request) }
}

extension Router: Semigroup {
    /// Tries `lhs`; falls through to `rhs` only on `.failure(.notFound)`.
    /// Both sub-routers are materialised once (inside the Reader), so `runReader` is
    /// called at most once per combined router — at server-start time.
    public static func combine(_ lhs: Router<Env>, _ rhs: Router<Env>) -> Router<Env> {
        Router(Reader { env in
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

extension Router: Monoid {
    public static var identity: Router<Env> { Router() }
}
