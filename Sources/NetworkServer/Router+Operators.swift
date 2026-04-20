import Core
import Foundation
import FP

// MARK: - Precedence

precedencegroup RouteHandlerPrecedence {
    associativity: left
    higherThan: ConcatPrecedence
}

infix operator =>: RouteHandlerPrecedence

// MARK: - Route => DecoderResult → TypedRoute

public func => <U: Decodable, Q: Decodable, B: Decodable>(
    _ route: Route<U, Q>,
    _ decoder: DecoderResult<B>
) -> TypedRoute<U, Q, B> {
    TypedRoute(route: route, bodyDecoder: decoder)
}

// MARK: - Route => Handler → Router  (Body == Empty)

public func => <U: Decodable & Sendable, Q: Decodable & Sendable, Env: Sendable>(
    _ route: Route<U, Q>,
    _ handler: Handler<U, Q, Empty, Env>
) -> Router<Env> {
    route => DecoderResult { _ in .success(.value) } => handler
}

// MARK: - TypedRoute => Handler → Router

public func => <U: Decodable & Sendable, Q: Decodable & Sendable, B: Decodable & Sendable, Env: Sendable>(
    _ typedRoute: TypedRoute<U, Q, B>,
    _ handler: Handler<U, Q, B, Env>
) -> Router<Env> {
    Router { request in
        switch typedRoute.route.match(request) {
        case .failure(let error):
            return .failure(error)
        case .success(let matched):
            let bodyData = matched.raw.body.isEmpty ? Data("{}".utf8) : matched.raw.body
            switch typedRoute.bodyDecoder.run(bodyData) {
            case .failure(let error):
                return .failure(.badRequest(error.localizedDescription))
            case .success(let body):
                let typedReq = TypedRequest(
                    urlParams: matched.urlParams,
                    queryParams: matched.queryParams,
                    body: body,
                    raw: matched.raw
                )
                return .success(handler.run(typedReq))
            }
        }
    }
}
