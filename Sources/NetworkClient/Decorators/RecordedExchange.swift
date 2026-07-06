// SPDX-License-Identifier: Apache-2.0

import Foundation

// Optional collections are intentional here: a `RecordedExchange` is a Codable snapshot DTO where an
// absent field (no request headers, no body) is meaningfully distinct from an empty one and is simply
// omitted from the on-disk file, keeping hand-authored fixtures terse.
// swiftlint:disable discouraged_optional_collection

/// One recorded request/response exchange — the on-disk unit for the record & replay decorators.
///
/// `Codable` so it can be persisted through *any* `DataEncoderFactory` / `DataDecoderFactory`
/// (JSON, Plist, XML, YAML — whatever the caller implements). Fields are optional where a
/// hand-written fixture can reasonably omit them, so authoring stubs by hand stays terse.
public struct RecordedExchange: Codable, Sendable, Equatable {
    // Request
    public let method: String
    public let url: String
    public let requestHeaders: [String: String]?
    public let requestBody: Data?
    // Response
    public let statusCode: Int
    public let responseHeaders: [String: String]?
    public let responseBody: Data
    // Metadata
    public let date: Date?

    public init(
        method: String,
        url: String,
        requestHeaders: [String: String]? = nil,
        requestBody: Data? = nil,
        statusCode: Int,
        responseHeaders: [String: String]? = nil,
        responseBody: Data,
        date: Date? = nil
    ) {
        self.method = method
        self.url = url
        self.requestHeaders = requestHeaders
        self.requestBody = requestBody
        self.statusCode = statusCode
        self.responseHeaders = responseHeaders
        self.responseBody = responseBody
        self.date = date
    }
}

// MARK: - Capture / reconstruct

public extension RecordedExchange {
    /// Builds an exchange from a live request and its successful `(Data, HTTPURLResponse)` response.
    init(request: URLRequest, responseBody: Data, response: HTTPURLResponse, date: Date?) {
        self.init(
            method: request.httpMethod ?? "GET",
            url: request.url?.absoluteString ?? "",
            requestHeaders: request.allHTTPHeaderFields,
            requestBody: request.httpBody,
            statusCode: response.statusCode,
            responseHeaders: response.allHeaderFields as? [String: String],
            responseBody: responseBody,
            date: date
        )
    }

    /// Rebuilds the raw `(Data, HTTPURLResponse)` result this exchange represents (replays status + headers + body).
    func asResponse() -> HTTPRequester.Response {
        guard let responseURL = URL(string: url) else { return .failure(.network(URLError(.badURL))) }
        return makeResponse(url: responseURL, status: statusCode, headers: responseHeaders ?? [:], body: responseBody)
    }
}

// swiftlint:enable discouraged_optional_collection
