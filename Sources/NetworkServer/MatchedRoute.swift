// SPDX-License-Identifier: Apache-2.0

#if canImport(NIOCore)
public struct MatchedRoute<URLParams: Sendable, QueryParams: Sendable>: Sendable {
    public let urlParams: URLParams
    public let queryParams: QueryParams
    public let raw: Request
}
#endif
