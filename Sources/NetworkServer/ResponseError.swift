import Core
import Foundation
import NIOHTTP1

public struct ResponseError: Error, @unchecked Sendable {
    public let status: HTTPResponseStatus
    public let headers: [(String, String)]
    public let body: Data

    public init(status: HTTPResponseStatus, headers: [(String, String)] = [], body: Data = Data()) {
        self.status  = status
        self.headers = headers
        self.body    = body
    }
}

// MARK: - Common errors

public extension ResponseError {
    static var notFound: ResponseError {
        ResponseError(status: .notFound, headers: [("Content-Type", "text/plain")], body: Data("Not Found".utf8))
    }

    static func badRequest(_ msg: String = "") -> ResponseError {
        ResponseError(status: .badRequest, headers: [("Content-Type", "text/plain")], body: Data(msg.utf8))
    }

    static func serverError(_ msg: String = "") -> ResponseError {
        ResponseError(status: .internalServerError, headers: [("Content-Type", "text/plain")], body: Data(msg.utf8))
    }
}

// MARK: - Encoded errors

public extension ResponseError {
    init<T>(_ value: T, encoder: ResponseEncoder<T>, status: HTTPResponseStatus = .internalServerError) {
        switch encoder.callAsFunction(value) {
        case .success(let data):
            self.init(status: status, headers: [("Content-Type", encoder.contentType)], body: data)
        case .failure(let e):
            self.init(status: .internalServerError, body: Data(e.localizedDescription.utf8))
        }
    }
}
