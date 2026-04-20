import Foundation
import NIOHTTP1

public struct Response: @unchecked Sendable {
    public let status: HTTPResponseStatus
    public let headers: [(String, String)]
    public let body: Data

    public init(
        status: HTTPResponseStatus = .ok,
        headers: [(String, String)] = [],
        body: Data = Data()
    ) {
        self.status  = status
        self.headers = headers
        self.body    = body
    }

    init(_ error: ResponseError) {
        self.init(status: error.status, headers: error.headers, body: error.body)
    }
}
