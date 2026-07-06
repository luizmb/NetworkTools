// SPDX-License-Identifier: Apache-2.0

import Core
import FP
import ReactiveConcurrency

// MARK: - Domain typealiases for the HTTP routing pipeline

//
// A pipeline step is a Kleisli arrow in `ReaderTPublisher`: `(I) -> Reader<Env, Publisher<O, ResponseError>>`.
// Steps compose with `>=>` from ReactiveConcurrencyOperators.

/// A step in the HTTP request-processing pipeline.
public typealias RouteStep<I: Sendable, Env: Sendable, O: Sendable> =
    @Sendable (I) -> Reader<Env, Publisher<O, ResponseError>>

/// Route matching step: dispatches a raw `Request` to a `MatchedRoute<U, Q>`.
public typealias RouteMatcher<U: Sendable, Q: Sendable, Env: Sendable> =
    RouteStep<Request, Env, MatchedRoute<U, Q>>

/// Body decoding step: promotes a `MatchedRoute` to a fully typed `TypedRequest<U, Q, B>`.
public typealias BodyDecoder<U: Sendable, Q: Sendable, B: Sendable, Env: Sendable> =
    RouteStep<MatchedRoute<U, Q>, Env, TypedRequest<U, Q, B>>

/// Terminal handler: produces a `Response` from a fully typed `TypedRequest<U, Q, B>`.
public typealias ResponseHandler<U: Sendable, Q: Sendable, B: Sendable, Env: Sendable> =
    RouteStep<TypedRequest<U, Q, B>, Env, Response>

/// Full pipeline: maps a `Request` directly to a `Response` within `Env`.
public typealias RoutePipeline<Env: Sendable> =
    RouteStep<Request, Env, Response>

// MARK: - response — NetworkServer terminal-handler entry points

/// Terminal handler from a synchronous `(TypedRequest, Env) -> Result`.
public func response<U, Q, B, Env: Sendable>(
    _ handler: @escaping @Sendable (TypedRequest<U, Q, B>, Env) -> Result<Response, ResponseError>
) -> ResponseHandler<U, Q, B, Env> {
    { req in Reader { env in Publisher.future { handler(req, env) } } }
}

/// Terminal handler from a synchronous `(TypedRequest) -> Result`.
public func response<U, Q, B, Env: Sendable>(
    _ handler: @escaping @Sendable (TypedRequest<U, Q, B>) -> Result<Response, ResponseError>
) -> ResponseHandler<U, Q, B, Env> {
    { req in Reader { _ in Publisher.future { handler(req) } } }
}

/// Terminal handler from an async `(TypedRequest, Env) -> Publisher`.
public func response<U, Q, B, Env: Sendable>(
    _ handler: @escaping @Sendable (TypedRequest<U, Q, B>, Env) -> Publisher<Response, ResponseError>
) -> ResponseHandler<U, Q, B, Env> {
    { req in Reader { env in handler(req, env) } }
}

/// Terminal handler from an async `(TypedRequest) -> Publisher`.
public func response<U, Q, B, Env: Sendable>(
    _ handler: @escaping @Sendable (TypedRequest<U, Q, B>) -> Publisher<Response, ResponseError>
) -> ResponseHandler<U, Q, B, Env> {
    { req in Reader { _ in handler(req) } }
}
