import Testing
import Combine
import Foundation
import NIOHTTP1
@testable import NetworkServer

// MARK: - Helpers

private func firstValue<O>(of publisher: AnyPublisher<O, Never>) -> O? {
    var result: O?
    let token = publisher.first().sink { result = $0 }
    withExtendedLifetime(token) {}
    return result
}

private extension Result {
    var isSuccess: Bool { if case .success = self { true } else { false } }
    var isFailure: Bool { !isSuccess }
}

// MARK: - Request

@Suite("Request")
struct RequestTests {
    @Test func pathStripsQuery() {
        #expect(Request(method: .GET, uri: "/search?q=swift", body: Data()).path == "/search")
    }

    @Test func pathNoQuery() {
        #expect(Request(method: .GET, uri: "/albums/42", body: Data()).path == "/albums/42")
    }

    @Test func pathRoot() {
        #expect(Request(method: .GET, uri: "/", body: Data()).path == "/")
    }

    @Test func queryParamsSingle() {
        let params = Request(method: .GET, uri: "/items?page=2", body: Data()).queryParams
        #expect(params == ["page": "2"])
    }

    @Test func queryParamsMultiple() {
        let params = Request(method: .GET, uri: "/items?page=1&limit=10", body: Data()).queryParams
        #expect(params["page"] == "1")
        #expect(params["limit"] == "10")
    }

    @Test func queryParamsEmpty() {
        #expect(Request(method: .GET, uri: "/items", body: Data()).queryParams.isEmpty)
    }

    @Test func queryParamsPercentDecoded() {
        let params = Request(method: .GET, uri: "/search?q=hello%20world", body: Data()).queryParams
        #expect(params["q"] == "hello world")
    }

    @Test func pathParamsMutable() {
        var req = Request(method: .GET, uri: "/albums/7", body: Data())
        req.pathParams = ["id": "7"]
        #expect(req.pathParams["id"] == "7")
    }

    @Test func decodeBody_success() throws {
        struct Item: Codable, Equatable { let name: String }
        let body = Data(#"{"name":"test"}"#.utf8)
        #expect(try Request(method: .POST, uri: "/", body: body).decodeBody(as: Item.self).get() == Item(name: "test"))
    }

    @Test func decodeBody_failure() {
        #expect(Request(method: .POST, uri: "/", body: Data("bad".utf8)).decodeBody(as: Int.self).isFailure)
    }

    @Test func decodeBody_emptyBodyFails() {
        #expect(Request(method: .POST, uri: "/", body: Data()).decodeBody(as: [String: String].self).isFailure)
    }
}

// MARK: - Response

@Suite("Response")
struct ResponseTests {
    @Test func defaultInit() {
        let r = Response()
        #expect(r.status == .ok)
        #expect(r.headers.isEmpty)
        #expect(r.body.isEmpty)
    }

    @Test func html_body() {
        let r = Response.html("<h1>Hi</h1>")
        #expect(r.status == .ok)
        #expect(r.headers.contains { $0 == ("Content-Type", "text/html; charset=utf-8") })
        #expect(String(data: r.body, encoding: .utf8) == "<h1>Hi</h1>")
    }

    @Test func html_customStatus() {
        #expect(Response.html("x", status: .notFound).status == .notFound)
    }

    @Test func json_encodesValue() throws {
        struct Point: Codable { let x: Int; let y: Int }
        let r = Response.json(Point(x: 1, y: 2))
        #expect(r.status == .ok)
        #expect(r.headers.contains { $0 == ("Content-Type", "application/json") })
        let decoded = try JSONDecoder().decode(Point.self, from: r.body)
        #expect(decoded.x == 1 && decoded.y == 2)
    }

    @Test func json_customStatus() {
        #expect(Response.json(["k": "v"], status: .created).status == .created)
    }

    @Test func json_sortedKeys() {
        let r = Response.json(["b": 2, "a": 1])
        let raw = String(data: r.body, encoding: .utf8) ?? ""
        #expect(raw.range(of: "\"a\"")!.lowerBound < raw.range(of: "\"b\"")!.lowerBound)
    }

    @Test func image_jpeg() {
        let data = Data([0xFF, 0xD8])
        let r = Response.image(data)
        #expect(r.status == .ok)
        #expect(r.headers.contains { $0 == ("Content-Type", "image/jpeg") })
        #expect(r.body == data)
    }

    @Test func image_customMimeType() {
        #expect(Response.image(Data(), mimeType: "image/png").headers.contains { $0 == ("Content-Type", "image/png") })
    }

    @Test func notFound() {
        #expect(Response.notFound.status == .notFound)
    }

    @Test func badRequest_body() {
        let r = Response.badRequest("missing field")
        #expect(r.status == .badRequest)
        #expect(String(data: r.body, encoding: .utf8) == "missing field")
    }

    @Test func serverError_body() {
        let r = Response.serverError("oops")
        #expect(r.status == .internalServerError)
        #expect(String(data: r.body, encoding: .utf8) == "oops")
    }
}

// MARK: - Handler

@Suite("Handler")
struct HandlerTests {
    @Test func callAsFunction() {
        let h = Handler { req in Just(Response.html(req.path)).eraseToAnyPublisher() }
        let response = firstValue(of: h(Request(method: .GET, uri: "/hello", body: Data())))
        #expect(String(data: response!.body, encoding: .utf8) == "/hello")
    }

    @Test func runPropertyEquivalentToCallAsFunction() {
        let h   = Handler { _ in Just(Response.notFound).eraseToAnyPublisher() }
        let req = Request(method: .GET, uri: "/", body: Data())
        let via_call = firstValue(of: h(req))
        let via_run  = firstValue(of: h.run(req))
        #expect(via_call?.status == via_run?.status)
    }

    @Test func initAcceptsClosure() {
        // Ensures FunctionWrapper init compiles and round-trips correctly.
        let h = Handler { _ in Just(Response.html("ok")).eraseToAnyPublisher() }
        #expect(firstValue(of: h(Request(method: .GET, uri: "/", body: Data())))?.status == .ok)
    }
}

// MARK: - Router

@Suite("Router — route")
struct RouterRouteTests {
    private func req(_ method: HTTPMethod, _ uri: String) -> Request {
        Request(method: method, uri: uri, body: Data())
    }

    // Method matching
    @Test func matchesCorrectMethod() {
        #expect(route(.GET, "/foo", { _ in .notFound })(req(.GET, "/foo")) != nil)
    }
    @Test func rejectsWrongMethod() {
        #expect(route(.POST, "/foo", { _ in .notFound })(req(.GET, "/foo")) == nil)
    }
    @Test func matchesPOST() {
        #expect(route(.POST, "/foo", { _ in .notFound })(req(.POST, "/foo")) != nil)
    }

    // Path matching
    @Test func matchesExactPath() {
        #expect(route(.GET, "/users", { _ in .notFound })(req(.GET, "/users")) != nil)
    }
    @Test func rejectsPartialPath() {
        #expect(route(.GET, "/a/b", { _ in .notFound })(req(.GET, "/a")) == nil)
    }
    @Test func rejectsExtraSegment() {
        #expect(route(.GET, "/a", { _ in .notFound })(req(.GET, "/a/b")) == nil)
    }
    @Test func rejectsDifferentLiteral() {
        #expect(route(.GET, "/users", { _ in .notFound })(req(.GET, "/admins")) == nil)
    }

    // Path params
    @Test func capturesSingleParam() {
        var captured: String?
        let matcher = route(.GET, "/users/:id") { r -> Response in captured = r.pathParams["id"]; return .notFound }
        _ = firstValue(of: matcher(req(.GET, "/users/42"))!)
        #expect(captured == "42")
    }

    @Test func capturesMultipleParams() {
        var params: [String: String]?
        let matcher = route(.GET, "/albums/:albumId/photos/:photoId") { r -> Response in params = r.pathParams; return .notFound }
        _ = firstValue(of: matcher(req(.GET, "/albums/5/photos/99"))!)
        #expect(params?["albumId"] == "5")
        #expect(params?["photoId"] == "99")
    }

    @Test func paramSegmentMismatchesLiteral() {
        // ":id" should capture even if it looks like a literal in the request
        let matcher = route(.GET, "/:id", { _ in .notFound })
        #expect(matcher(req(.GET, "/anything")) != nil)
    }

    @Test func asyncHandlerVariant() {
        let matcher = route(.GET, "/ping") { _ in Just(Response.html("pong")).eraseToAnyPublisher() }
        let r = firstValue(of: matcher(req(.GET, "/ping"))!)
        #expect(String(data: r!.body, encoding: .utf8) == "pong")
    }

    @Test func syncHandlerVariant() {
        let matcher = route(.DELETE, "/x", { _ in Response.html("deleted") })
        let r = firstValue(of: matcher(req(.DELETE, "/x"))!)
        #expect(String(data: r!.body, encoding: .utf8) == "deleted")
    }
}

@Suite("Router — firstMatch")
struct RouterFirstMatchTests {
    private func req(_ method: HTTPMethod, _ uri: String) -> Request {
        Request(method: method, uri: uri, body: Data())
    }

    @Test func returnsNotFoundForEmptyRoutes() {
        let h = firstMatch([])
        #expect(firstValue(of: h(req(.GET, "/")))?.status == .notFound)
    }

    @Test func returnsNotFoundWhenNothingMatches() {
        let h = firstMatch([route(.GET, "/a", { _ in .html("A") })])
        #expect(firstValue(of: h(req(.GET, "/b")))?.status == .notFound)
    }

    @Test func returnsFirstMatchingRoute() {
        let routes: [RouteMatcher] = [
            route(.GET, "/a", { _ in .html("A") }),
            route(.GET, "/b", { _ in .html("B") }),
        ]
        let h = firstMatch(routes)
        #expect(String(data: firstValue(of: h(req(.GET, "/a")))!.body, encoding: .utf8) == "A")
        #expect(String(data: firstValue(of: h(req(.GET, "/b")))!.body, encoding: .utf8) == "B")
    }

    @Test func stopsAtFirstMatch() {
        var secondCalled = false
        let routes: [RouteMatcher] = [
            route(.GET, "/x", { _ in .html("first") }),
            route(.GET, "/x") { _ -> Response in secondCalled = true; return .html("second") },
        ]
        _ = firstValue(of: firstMatch(routes)(req(.GET, "/x")))
        #expect(!secondCalled)
    }

    @Test func skipsNonMatchingMethod() {
        let routes: [RouteMatcher] = [
            route(.POST, "/x", { _ in .html("post") }),
            route(.GET,  "/x", { _ in .html("get")  }),
        ]
        let body = String(data: firstValue(of: firstMatch(routes)(req(.GET, "/x")))!.body, encoding: .utf8)
        #expect(body == "get")
    }

    @Test func handlerIsAFunctionWrapper() {
        // firstMatch returns Handler (FunctionWrapper), not a plain closure.
        let h: Handler = firstMatch([])
        let _ = h.run  // access the wrapped function directly
        #expect(Bool(true))  // compile-time check
    }
}

// MARK: - NIOServer

@Suite("NIOServer")
struct NIOServerTests {

    @Test func startServer_returnsReaderOverHandler() {
        // Type-level verification: Reader<Handler, Result<Void, Error>>
        let reader = startServer(port: 0)
        let _: (Handler) -> Result<Void, Error> = reader.runReader
        #expect(Bool(true))
    }

    @Test func startServer_failsOnOutOfRangePort() {
        let result = startServer(host: "127.0.0.1", port: 99999).runReader(
            Handler { _ in Just(.notFound).eraseToAnyPublisher() }
        )
        #expect(result.isFailure)
    }

    @Test(.timeLimit(.minutes(1)))
    func startServer_respondsToRequest() async throws {
        let port = 18_091
        let handler = Handler { req in
            Just(Response.html("OK:\(req.path)")).eraseToAnyPublisher()
        }
        Thread.detachNewThread {
            _ = startServer(port: port).runReader(handler)
        }
        // Allow NIO to bind and accept connections.
        try await Task.sleep(for: .milliseconds(300))

        var urlRequest = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/hello")!)
        urlRequest.timeoutInterval = 5
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(data: data, encoding: .utf8) == "OK:/hello")
    }

    @Test(.timeLimit(.minutes(1)))
    func startServer_routesRequests() async throws {
        let port = 18_092
        let routes: [RouteMatcher] = [
            route(.GET,  "/ping", { _ in .html("pong") }),
            route(.POST, "/echo") { req in
                Response.html(String(data: req.body, encoding: .utf8) ?? "")
            },
        ]
        Thread.detachNewThread {
            _ = startServer(port: port).runReader(firstMatch(routes))
        }
        try await Task.sleep(for: .milliseconds(300))

        // GET /ping
        let (pingData, pingResp) = try await URLSession.shared.data(
            from: URL(string: "http://127.0.0.1:\(port)/ping")!
        )
        #expect((pingResp as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(data: pingData, encoding: .utf8) == "pong")

        // POST /echo
        var echoReq = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/echo")!)
        echoReq.httpMethod = "POST"
        echoReq.httpBody   = Data("hello".utf8)
        let (echoData, _)  = try await URLSession.shared.data(for: echoReq)
        #expect(String(data: echoData, encoding: .utf8) == "hello")

        // Unmatched route → 404
        let (_, notFoundResp) = try await URLSession.shared.data(
            from: URL(string: "http://127.0.0.1:\(port)/missing")!
        )
        #expect((notFoundResp as? HTTPURLResponse)?.statusCode == 404)
    }
}
