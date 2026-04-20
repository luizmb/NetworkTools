import FP
import Foundation

public struct Router<Env: Sendable>: @unchecked Sendable {
    private var entries: [(Request) -> Reader<Env, DeferredTask<Result<Response, ResponseError>>>?] = []

    public init() {}

    public mutating func register<U: Decodable & Sendable, Q: Decodable & Sendable, B: Decodable & Sendable>(
        route: Route<U, Q>,
        decoder: RequestDecoder<U, Q, B>,
        handler: Handler<U, Q, B, Env>
    ) {
        entries.append { request in
            switch route.match(request) {
            case nil:
                return nil
            case .failure(let error):
                return Reader { _ in DeferredTask { .failure(error) } }
            case .success(let matched):
                switch decoder.decode(matched) {
                case .failure(let error):
                    return Reader { _ in DeferredTask { .failure(error) } }
                case .success(let typedReq):
                    return handler.run(typedReq)
                }
            }
        }
    }

    public func handle(_ request: Request) -> Reader<Env, DeferredTask<Result<Response, ResponseError>>> {
        let matched = entries.compactMap { $0(request) }.first
        return Reader { env in matched?.runReader(env) ?? DeferredTask { .failure(.notFound) } }
    }
}
