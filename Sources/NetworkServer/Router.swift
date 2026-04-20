import Core
import FP
import Foundation

public struct Router<Env: Sendable>: @unchecked Sendable {
    private var entries: [(Request) -> Reader<Env, DeferredTask<Result<Response, ResponseError>>>?] = []

    public init() {}

    public mutating func register<U: Decodable & Sendable, Q: Decodable & Sendable, B: Decodable & Sendable>(
        route: Route<U, Q>,
        bodyDecoder: DecoderResult<B>,
        handler: Handler<U, Q, B, Env>
    ) {
        entries.append { request in
            switch route.match(request) {
            case nil:
                return nil
            case .failure(let error):
                return Reader { _ in DeferredTask { .failure(error) } }
            case .success(let matched):
                let bodyData = matched.raw.body.isEmpty ? Data("{}".utf8) : matched.raw.body
                switch bodyDecoder.run(bodyData) {
                case .failure(let error):
                    return Reader { _ in DeferredTask { .failure(.badRequest(error.localizedDescription)) } }
                case .success(let body):
                    let typedReq = TypedRequest(urlParams: matched.urlParams, queryParams: matched.queryParams, body: body, raw: matched.raw)
                    return handler.run(typedReq)
                }
            }
        }
    }

    public mutating func register<U: Decodable & Sendable, Q: Decodable & Sendable>(
        route: Route<U, Q>,
        handler: Handler<U, Q, Empty, Env>
    ) {
        register(route: route, bodyDecoder: DecoderResult { _ in .success(.value) }, handler: handler)
    }

    public func handle(_ request: Request) -> Reader<Env, DeferredTask<Result<Response, ResponseError>>> {
        let matched = entries.compactMap { $0(request) }.first
        return Reader { env in matched?.runReader(env) ?? DeferredTask { .failure(.notFound) } }
    }
}
