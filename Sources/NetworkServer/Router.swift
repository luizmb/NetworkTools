import Core
import Foundation
import FP

public struct Router<Env: Sendable>: @unchecked Sendable {
    public let handle: RoutePipeline<Env>

    public init(_ handle: RoutePipeline<Env>) {
        self.handle = handle
    }

    /// The empty router — always returns 404. Identity for `<|>`.
    public static var empty: Router<Env> {
        Router(RoutePipeline { _ in ZIO { _ in DeferredTask { .failure(.notFound) } } })
    }

    public func contramap<World: Sendable>(_ f: @escaping @Sendable (World) -> Env) -> Router<World> {
        Router<World>(RoutePipeline { [handle] request in
            ZIO { world in handle.run(request).run(f(world)) }
        })
    }
}

// MARK: - Alternative

struct SendableHandler: @unchecked Sendable {
    let call: (Request) -> DeferredTask<Result<Response, ResponseError>>
    func callAsFunction(_ request: Request) -> DeferredTask<Result<Response, ResponseError>> { call(request) }
}

extension Router {
    /// Ordered choice: try `lhs`; fall through to `rhs` only on `.failure(.notFound)`.
    public static func alt(_ lhs: Router<Env>, _ rhs: @autoclosure () -> Router<Env>) -> Router<Env> {
        let rhs = rhs()
        return Router(RoutePipeline { [lh = lhs.handle, rh = rhs.handle] request in
            let l = lh.run(request)
            let r = rh.run(request)
            return ZIO { env in
                DeferredTask {
                    let result = await l.run(env).run()
                    if case .failure(let e) = result, e.status == .notFound {
                        return await r.run(env).run()
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
