// SPDX-License-Identifier: Apache-2.0

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import FP
import ReactiveConcurrency

/// A composable HTTP client — the single requester abstraction.
///
/// `HTTPClient` is a pure function `@Sendable (URLRequest) -> Publisher<(Data, HTTPURLResponse),
/// HTTPError>`. `URLRequest` is an ordinary value (a DTO), so this is a plain function wrapper, not a
/// `Reader`. Behaviour is layered on with **decorators** — `Endo<HTTPClient>` values applied by
/// calling them on a base and nesting to compose:
///
/// ```swift
/// let client = HTTPClient.record(to: store)(          // …then record everything
///     HTTPClient.override(on: .path("/mocked"),       // mock one endpoint…
///                         use: .const(.ok(body: json)))(
///         HTTPClient.live(session: .shared)
///     )
/// )
/// let typed = client(request).validateStatusCode().decode(using: JSONDecoder(), type: User.self)
/// ```
public struct HTTPClient: Sendable {
    /// The raw HTTP response pair, or an ``HTTPError``.
    public typealias Response = Result<(Data, HTTPURLResponse), HTTPError>

    public let requester: @Sendable (URLRequest) -> Publisher<(Data, HTTPURLResponse), HTTPError>

    public init(_ requester: @escaping @Sendable (URLRequest) -> Publisher<(Data, HTTPURLResponse), HTTPError>) {
        self.requester = requester
    }

    public func callAsFunction(_ request: URLRequest) -> Publisher<(Data, HTTPURLResponse), HTTPError> {
        requester(request)
    }
}

// MARK: - Factories

public extension HTTPClient {
    /// A live client backed by a `URLSession`.
    static func live(session: URLSession) -> HTTPClient {
        HTTPClient { request in
            Publisher.future {
                do {
                    let (data, response) = try await session.data(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        return .failure(.network(URLError(.badServerResponse)))
                    }
                    return .success((data, http))
                } catch {
                    return .failure(.network(error))
                }
            }
        }
    }

    /// A client that always returns a fixed result, ignoring the request.
    static func const(_ result: Response) -> HTTPClient {
        HTTPClient { _ in result.publisher }
    }

    /// A client whose response is built from a ``StubResponse`` (applied to a synthetic `200` seed).
    /// Compose the response from pieces: `.const(.ok(body: json) <> .withStatus(201))`.
    static func const(_ response: StubResponse) -> HTTPClient {
        HTTPClient { request in
            response.response(for: request, incoming: StubResponse.seed(for: request)).publisher
        }
    }
}
