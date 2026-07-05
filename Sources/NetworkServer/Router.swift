import Core
import Foundation
import FP
import ReactiveConcurrency

public struct Router<Env: Sendable>: @unchecked Sendable {
    public let handle: RoutePipeline<Env>

    public init(_ handle: @escaping RoutePipeline<Env>) {
        self.handle = handle
    }

    /// The empty router — always returns 404. Identity for `<|>`.
    public static var empty: Router<Env> {
        Router { _ in Reader { _ in Publisher.future { .failure(.notFound) } } }
    }

    public func contramap<World: Sendable>(_ f: @escaping @Sendable (World) -> Env) -> Router<World> {
        Router<World>({ [handle] request in
            Reader { world in handle(request)(f(world)) }
        })
    }
}

// MARK: - Alternative

struct SendableHandler: @unchecked Sendable {
    let call: @Sendable (Request) -> Publisher<Response, ResponseError>
    func callAsFunction(_ request: Request) -> Publisher<Response, ResponseError> { call(request) }
}

extension Router {
    /// Ordered choice: try `lhs`; fall through to `rhs` only on `.failure(.notFound)`.
    public static func alt(_ lhs: Router<Env>, _ rhs: @autoclosure () -> Router<Env>) -> Router<Env> {
        let rhs = rhs()
        return Router({ [lh = lhs.handle, rh = rhs.handle] request in
            Reader { env in
                lh(request)(env).`catch` { error in
                    error.status == .notFound ? rh(request)(env) : Publisher.fail(error)
                }
            }
        })
    }
}

public func <|> <Env: Sendable>(_ lhs: Router<Env>, _ rhs: @autoclosure () -> Router<Env>) -> Router<Env> {
    Router.alt(lhs, rhs())
}
