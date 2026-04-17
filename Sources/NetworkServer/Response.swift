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
}

// MARK: - Smart constructors

public extension Response {

    static func html(_ html: String, status: HTTPResponseStatus = .ok) -> Response {
        Response(
            status: status,
            headers: [("Content-Type", "text/html; charset=utf-8")],
            body: Data(html.utf8)
        )
    }

    static func json<T: Encodable>(_ value: T, status: HTTPResponseStatus = .ok) -> Response {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let headers = [("Content-Type", "application/json")]
        switch Result(catching: { try encoder.encode(value) }) {
        case .success(let data):
            return Response(status: status, headers: headers, body: data)
        case .failure(let error):
            let body = Data(#"{"error":"encoding_failed"}"#.utf8)
            print("[NetworkServer] JSON encoding error: \(error)")
            return Response(status: .internalServerError, headers: headers, body: body)
        }
    }

    static func image(_ data: Data, mimeType: String = "image/jpeg") -> Response {
        Response(
            status: .ok,
            headers: [("Content-Type", mimeType)],
            body: data
        )
    }

    static var notFound: Response {
        Response(
            status: .notFound,
            headers: [("Content-Type", "text/plain")],
            body: Data("Not Found".utf8)
        )
    }

    static func badRequest(_ msg: String) -> Response {
        Response(
            status: .badRequest,
            headers: [("Content-Type", "text/plain")],
            body: Data(msg.utf8)
        )
    }

    static func serverError(_ msg: String) -> Response {
        Response(
            status: .internalServerError,
            headers: [("Content-Type", "text/plain")],
            body: Data(msg.utf8)
        )
    }
}
