import Core
import Foundation
import FP

public struct Router<Env: Sendable>: @unchecked Sendable {
    public let run: (Request) -> Result<Reader<Env, DeferredTask<Result<Response, ResponseError>>>, ResponseError>

    public init(_ run: @escaping (Request) -> Result<Reader<Env, DeferredTask<Result<Response, ResponseError>>>, ResponseError>) {
        self.run = run
    }

    public init() {
        run = { _ in .failure(.notFound) }
    }

    public func handle(_ request: Request) -> Reader<Env, DeferredTask<Result<Response, ResponseError>>> {
        switch run(request) {
        case .success(let reader):
            reader
        case .failure(let error):
            Reader { _ in DeferredTask { .failure(error) } }
        }
    }

    public func pullback<World: Sendable>(_ f: @escaping (World) -> Env) -> Router<World> {
        Router<World> { request in
            self.run(request).map { reader in
                Reader { world in reader.runReader(f(world)) }
            }
        }
    }
}

// MARK: - Semigroup / Monoid

extension Router: Semigroup {
    public static func combine(_ lhs: Router<Env>, _ rhs: Router<Env>) -> Router<Env> {
        Router { request in
            switch lhs.run(request) {
            case .failure(let e) where e.status == .notFound:
                rhs.run(request)
            case let result:
                result
            }
        }
    }
}

extension Router: Monoid {
    public static var identity: Router<Env> { Router { _ in .failure(.notFound) } }
}
