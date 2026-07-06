// SPDX-License-Identifier: Apache-2.0

import Core
import Foundation
import FP

/// The "what response?" atom — a request-aware `Endo` over the raw HTTP result, shared by the
/// override and replay decorators.
///
/// A `StubResponse` is fundamentally `Result<(Data, HTTPURLResponse), HTTPError> -> Result<…>`,
/// curried over the `URLRequest` so a builder can read the request (its URL is needed to construct a
/// synthetic `HTTPURLResponse`, and matched values can be echoed back). Because it is an `Endo`, you
/// **compose** small pieces with `<>` to assemble simple or complex responses, changing only what
/// you need on top of sensible defaults (200, no headers, empty body):
///
/// ```swift
/// .ok(body: json)                                   // 200 + body
/// .ok() <> .status(201) <> .header("ETag", "\"v1\"")  // build up piece by piece
/// .failure(.network(URLError(.notConnectedToInternet)))  // simulate a transport error
/// .json(user) <> .withDelay(.milliseconds(300))     // encode + simulate latency
/// ```
///
/// The result is lifted into the reactive stack by the decorator via `Result.publisher`, so this
/// type is completely independent of Combine vs ReactiveConcurrency.
public struct StubResponse: Sendable {
    /// Given the request, an `Endo` transforming an incoming (real or seed) response into the outgoing one.
    public let endo: @Sendable (URLRequest) -> Endo<HTTPRequester.Response>
    /// Optional artificial latency before the response is emitted (the decorator applies it with an injected clock).
    public let delay: Duration

    public init(
        delay: Duration = .zero,
        _ endo: @escaping @Sendable (URLRequest) -> Endo<HTTPRequester.Response>
    ) {
        self.endo = endo
        self.delay = delay
    }

    /// Applies the stub to `request`, transforming `incoming` (the base response, or a 200/empty seed
    /// for overrides that don't hit the network).
    public func response(for request: URLRequest, incoming: HTTPRequester.Response) -> HTTPRequester.Response {
        endo(request).runEndo(incoming)
    }

    /// A synthetic seed for overrides: an empty 200 for the request's URL (or `.badURL` if it has none).
    public static func seed(for request: URLRequest) -> HTTPRequester.Response {
        makeResponse(request: request, status: 200, headers: [:], body: Data())
    }
}

// MARK: - Constructors (ignore the incoming response — build from scratch)

public extension StubResponse {
    /// Replace the response wholesale, ignoring anything incoming. This is `FP.const` at the `Result` level.
    static func const(_ make: @escaping @Sendable (URLRequest) -> HTTPRequester.Response) -> StubResponse {
        StubResponse { request in Endo { _ in make(request) } }
    }

    /// A `200 OK` with an optional body and no headers.
    static func ok(body: Data = Data()) -> StubResponse {
        status(200, body: body)
    }

    /// A response with an explicit status, optional headers, and optional body. Defaults keep it terse.
    static func status(_ code: Int, headers: [String: String] = [:], body: Data = Data()) -> StubResponse {
        .const { request in makeResponse(request: request, status: code, headers: headers, body: body) }
    }

    /// A JSON body encoded via any `DataEncoderFactory`, with `Content-Type: application/json`.
    static func json<Value: Encodable & Sendable>(
        _ value: Value,
        status code: Int = 200,
        encoder: DataEncoderFactory
    ) -> StubResponse {
        // Encode once, eagerly — the body doesn't depend on the request, and `DataEncoderFactory`
        // isn't Sendable so it must not be captured in the @Sendable builder closure.
        let encoded: Result<Data, HTTPError> = encoder.dataEncoder(for: Value.self).run(value).mapError(HTTPError.network)
        return .const { request in
            encoded.flatMap { data in
                makeResponse(request: request, status: code, headers: ["Content-Type": "application/json"], body: data)
            }
        }
    }

    /// Simulate a failure (transport / decode error) instead of a response.
    static func failure(_ error: HTTPError) -> StubResponse {
        StubResponse { _ in Endo { _ in .failure(error) } }
    }

    /// The identity stub — passes the incoming response through unchanged. The `<>` unit.
    static let passthrough = StubResponse { _ in Endo { $0 } }
}

// MARK: - Modifiers (transform the incoming response)

public extension StubResponse {
    /// Overrides the status code, preserving URL, headers and body.
    static func withStatus(_ code: Int) -> StubResponse {
        rewriting { _, url, headers, body in makeResponse(url: url, status: code, headers: headers, body: body) }
    }

    /// Adds/replaces a single response header.
    static func withHeader(_ name: String, _ value: String) -> StubResponse {
        withHeaders([name: value])
    }

    /// Merges the given headers into the response headers (new values win).
    static func withHeaders(_ extra: [String: String]) -> StubResponse {
        rewriting { status, url, headers, body in
            makeResponse(url: url, status: status, headers: headers.merging(extra) { _, new in new }, body: body)
        }
    }

    /// Replaces the response body.
    static func withBody(_ data: Data) -> StubResponse {
        rewriting { status, url, headers, _ in makeResponse(url: url, status: status, headers: headers, body: data) }
    }

    /// Adds artificial latency before emission (the decorator applies it with an injected clock).
    static func withDelay(_ delay: Duration) -> StubResponse {
        StubResponse(delay: delay) { _ in Endo { $0 } }
    }
}

// MARK: - Composition (Endo semigroup: left then right; the right non-zero delay wins)

public extension StubResponse {
    static func <> (lhs: StubResponse, rhs: StubResponse) -> StubResponse {
        StubResponse(delay: rhs.delay != .zero ? rhs.delay : lhs.delay) { request in
            Endo { incoming in rhs.endo(request).runEndo(lhs.endo(request).runEndo(incoming)) }
        }
    }
}

// MARK: - Response construction helpers

/// Rebuilds the response on the success branch from its (status, url, headers, body); leaves failures untouched.
private func rewriting(
    _ f: @escaping @Sendable (Int, URL, [String: String], Data) -> HTTPRequester.Response
) -> StubResponse {
    StubResponse { _ in
        Endo { incoming in
            incoming.flatMap { data, response in
                guard let url = response.url else { return .failure(.network(URLError(.badURL))) }
                let headers = (response.allHeaderFields as? [String: String]) ?? [:]
                return f(response.statusCode, url, headers, data)
            }
        }
    }
}

func makeResponse(request: URLRequest, status: Int, headers: [String: String], body: Data) -> HTTPRequester.Response {
    guard let url = request.url else { return .failure(.network(URLError(.badURL))) }
    return makeResponse(url: url, status: status, headers: headers, body: body)
}

func makeResponse(url: URL, status: Int, headers: [String: String], body: Data) -> HTTPRequester.Response {
    guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers) else {
        return .failure(.network(URLError(.badServerResponse)))
    }
    return .success((body, response))
}
