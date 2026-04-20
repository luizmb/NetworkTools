import Core
import Foundation
import FP

// MARK: - Bridge: (A -> Reader<Env, Result<B, E>>) >=> (B -> Reader<Env, DeferredTask<Result<C, E>>>)
//
// FP already provides:
//   >=>  for ReaderTResult  (both legs produce Reader<Env, Result<…>>)
//   >=>  for ReaderTDeferredTask (both legs produce Reader<Env, DeferredTask<…>>)
//
// This overload bridges the two: the sync routing/decoding phase (ReaderTResult)
// into the async handler phase (ReaderTDeferredTaskResult).

public func >=> <Env: Sendable, A, B, C, E: Error>(
    _ fn1: @escaping (A) -> Reader<Env, Result<B, E>>,
    _ fn2: @escaping (B) -> Reader<Env, DeferredTask<Result<C, E>>>
) -> (A) -> Reader<Env, DeferredTask<Result<C, E>>> {
    { a in
        Reader { env in
            switch fn1(a).runReader(env) {
            case .failure(let e): DeferredTask { .failure(e) }
            case .success(let b): fn2(b).runReader(env)
            }
        }
    }
}

// MARK: - Route → Kleisli step

public extension Route {
    /// Lifts `match` into `Reader<Env, Result<…>>` for Kleisli composition via `>=>`.
    ///
    /// ```swift
    /// let router = Router(
    ///     route.matchReader() >=> decodeBody(bodyDecoder) >=> myHandler.run
    /// )
    /// ```
    func matchReader<Env>() -> (Request) -> Reader<Env, Result<MatchedRoute<URLParams, QueryParams>, ResponseError>> {
        { request in Reader { _ in self.match(request) } }
    }
}

// MARK: - Body-decode → Kleisli step

/// Lifts a `DecoderResult<B>` into `Reader<Env, Result<…>>` for Kleisli composition via `>=>`.
/// Applies the decoder to the raw request body; maps decode failures to `400 Bad Request`.
public func decodeBody<U, Q, B: Decodable, Env>(
    _ decoder: DecoderResult<B>
) -> (MatchedRoute<U, Q>) -> Reader<Env, Result<TypedRequest<U, Q, B>, ResponseError>> {
    { matched in
        Reader { _ in
            let bodyData = matched.raw.body.isEmpty ? Data("{}".utf8) : matched.raw.body
            return decoder.run(bodyData)
                .map { body in
                    TypedRequest(
                        urlParams: matched.urlParams,
                        queryParams: matched.queryParams,
                        body: body,
                        raw: matched.raw
                    )
                }
                .mapError { ResponseError.badRequest($0.localizedDescription) }
        }
    }
}

// MARK: - Router init from Kleisli chain

public extension Router {
    /// Wraps a Kleisli function `(Request) -> Reader<Env, DeferredTask<…>>` into a `Router`.
    ///
    /// The Kleisli form and the stored `Reader<Env, (Request) -> DeferredTask<…>>` are
    /// isomorphic via currying; this init performs that conversion so `runReader` is
    /// called once at server startup, not per request.
    ///
    /// ```swift
    /// let router = Router(
    ///     route.matchReader() >=> decodeBody(decoder) >=> handler.run
    /// )
    /// ```
    init(_ fn: @escaping (Request) -> Reader<Env, DeferredTask<Result<Response, ResponseError>>>) {
        self.init(Reader { env in { request in fn(request).runReader(env) } })
    }
}
