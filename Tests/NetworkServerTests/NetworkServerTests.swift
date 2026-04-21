// swiftlint:disable file_length
import Core
import Foundation
import FP
import NIOHTTP1
import Testing
#if canImport(Combine)
import Combine
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import NetworkServer

private typealias Empty = NetworkServer.Empty

// MARK: - Helpers

private extension Result {
    var isSuccess: Bool { if case .success = self { true } else { false } }
    var isFailure: Bool { !isSuccess }
}

private extension Result where Success == Response, Failure == ResponseError {
    var response: Response {
        switch self {
        case .success(let r): r
        case .failure(let e): Response(e)
        }
    }
}

private func jsonEncoder(_ configure: (JSONEncoder) -> Void = { _ in }) -> JSONEncoder {
    let e = JSONEncoder()
    configure(e)
    return e
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
        let result = Request(method: .POST, uri: "/", body: body).decodeBody(as: Item.self).runReader(JSONDecoder())
        #expect(try result.get() == Item(name: "test"))
    }

    @Test func decodeBody_failure() {
        #expect(Request(method: .POST, uri: "/", body: Data("bad".utf8)).decodeBody(as: Int.self).runReader(JSONDecoder()).isFailure)
    }

    @Test func decodeBody_emptyBodyFails() {
        #expect(Request(method: .POST, uri: "/", body: Data()).decodeBody(as: [String: String].self).runReader(JSONDecoder()).isFailure)
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
}

// MARK: - ResponseError

@Suite("ResponseError")
struct ResponseErrorTests {
    @Test func notFound() {
        #expect(ResponseError.notFound.status == .notFound)
    }

    @Test func badRequest_body() {
        let e = ResponseError.badRequest("missing field")
        #expect(e.status == .badRequest)
        #expect(String(data: e.body, encoding: .utf8) == "missing field")
    }

    @Test func serverError_body() {
        let e = ResponseError.serverError("oops")
        #expect(e.status == .internalServerError)
        #expect(String(data: e.body, encoding: .utf8) == "oops")
    }

    @Test func encodedJson() throws {
        struct Payload: Codable { let code: Int }
        let e = ResponseError.json(Payload(code: 42), encoder: jsonEncoder(), status: .unprocessableEntity)
        #expect(e.status == .unprocessableEntity)
        #expect(e.headers.contains { $0 == ("Content-Type", "application/json") })
        #expect(try JSONDecoder().decode(Payload.self, from: e.body).code == 42)
    }

    @Test func encodedHtml() {
        let e = ResponseError.html("<b>bad</b>", status: .badRequest)
        #expect(e.status == .badRequest)
        #expect(String(data: e.body, encoding: .utf8) == "<b>bad</b>")
    }
}

// MARK: - Result<Response, ResponseError> factories

@Suite("ResultResponse")
struct ResultResponseTests {
    @Test func html_encodesUTF8() throws {
        let r = try Result<Response, ResponseError>.html("<h1>Hi</h1>").get()
        #expect(r.status == .ok)
        #expect(r.headers.contains { $0 == ("Content-Type", "text/html; charset=utf-8") })
        #expect(String(data: r.body, encoding: .utf8) == "<h1>Hi</h1>")
    }

    @Test func html_customStatus() throws {
        #expect(try Result<Response, ResponseError>.html("x", status: .notFound).get().status == .notFound)
    }

    @Test func json_encodesValue() throws {
        struct Point: Codable { let x: Int; let y: Int }
        let r = try Result<Response, ResponseError>.json(Point(x: 1, y: 2), encoder: JSONEncoder()).get()
        #expect(r.status == .ok)
        #expect(r.headers.contains { $0 == ("Content-Type", "application/json") })
        let decoded = try JSONDecoder().decode(Point.self, from: r.body)
        #expect(decoded.x == 1 && decoded.y == 2)
    }

    @Test func json_customStatus() throws {
        struct S: Encodable { let k: String }
        #expect(try Result<Response, ResponseError>.json(S(k: "v"), encoder: JSONEncoder(), status: .created).get().status == .created)
    }

    @Test func json_sortedKeys() throws {
        let r = try Result<Response, ResponseError>.json(["b": 2, "a": 1], encoder: jsonEncoder { $0.outputFormatting = .sortedKeys }).get()
        let raw = String(data: r.body, encoding: .utf8) ?? ""
        let aRange = try #require(raw.range(of: "\"a\""))
        let bRange = try #require(raw.range(of: "\"b\""))
        #expect(aRange.lowerBound < bRange.lowerBound)
    }

    @Test func raw_isIdentity() throws {
        let data = Data([0x01, 0x02, 0x03])
        #expect(try Result<Response, ResponseError>.raw(data).get().body == data)
    }

    @Test func image_jpeg() throws {
        let data = Data([0xFF, 0xD8])
        let r = try Result<Response, ResponseError>.image(data).get()
        #expect(r.status == .ok)
        #expect(r.headers.contains { $0 == ("Content-Type", "image/jpeg") })
        #expect(r.body == data)
    }

    @Test func image_customMimeType() throws {
        let r = try Result<Response, ResponseError>.image(Data(), mimeType: "image/png").get()
        #expect(r.headers.contains { $0 == ("Content-Type", "image/png") })
    }
}

// MARK: - matchPath

@Suite("matchPath")
struct MatchPathTests {
    @Test func exactMatch() {
        #expect(matchPath("/a/b", against: "/a/b")?.isEmpty == true)
    }

    @Test func capturesSingleParam() {
        #expect(matchPath("/users/42", against: "/users/:id") == ["id": "42"])
    }

    @Test func capturesMultipleParams() {
        #expect(matchPath("/albums/5/photos/99", against: "/albums/:albumId/photos/:photoId")
            == ["albumId": "5", "photoId": "99"])
    }

    @Test func noMatchSegmentCountMismatch() {
        #expect(matchPath("/a", against: "/a/b") == nil)
    }

    @Test func noMatchDifferentLiteral() {
        #expect(matchPath("/a", against: "/b") == nil)
    }
}

// MARK: - Route

@Suite("Route")
struct RouteTests {
    private func req(_ method: HTTPMethod, _ uri: String) -> Request {
        Request(method: method, uri: uri, body: Data())
    }

    @Test func matchesMethodAndPath() {
        #expect(Route<Empty, Empty>(.GET, "/ping").match(req(.GET, "/ping")).isSuccess)
    }

    @Test func rejectsWrongMethod() {
        let result = Route<Empty, Empty>(.GET, "/ping").match(req(.POST, "/ping"))
        guard case .failure(let e) = result else { Issue.record("Expected .failure"); return }
        #expect(e.status == .notFound)
    }

    @Test func rejectsWrongPath() {
        let result = Route<Empty, Empty>(.GET, "/ping").match(req(.GET, "/pong"))
        guard case .failure(let e) = result else { Issue.record("Expected .failure"); return }
        #expect(e.status == .notFound)
    }

    @Test func decodesURLParams() {
        struct UserParams: Decodable { let id: String }
        let route = Route<UserParams, Empty>(.GET, "/users/:id")
        guard case .success(let mr) = route.match(req(.GET, "/users/42")) else {
            Issue.record("Expected .success"); return
        }
        #expect(mr.urlParams.id == "42")
    }

    @Test func returnsNotFoundOnURLParamTypeMismatch() {
        struct UserParams: Decodable { let id: Int }
        let result = Route<UserParams, Empty>(.GET, "/users/:id").match(req(.GET, "/users/abc"))
        guard case .failure(let e) = result else { Issue.record("Expected .failure"); return }
        #expect(e.status == .notFound)
    }

    @Test func returnsErrorOnMissingRequiredQueryParam() {
        struct Q: Decodable { let page: Int }
        guard case .failure(let e) = Route<Empty, Q>(.GET, "/items").match(req(.GET, "/items")) else {
            Issue.record("Expected .failure"); return
        }
        #expect(e.status == .badRequest)
    }

    @Test func decodesOptionalQueryParam() {
        struct Q: Decodable { let page: Int? }
        #expect(Route<Empty, Q>(.GET, "/items").match(req(.GET, "/items")).isSuccess)
    }
}

// MARK: - Router

@Suite("Router")
struct RouterTests {
    private func req(_ method: HTTPMethod, _ uri: String, body: Data = Data()) -> Request {
        Request(method: method, uri: uri, body: body)
    }

    @Test func notFoundForEmptyRouter() async {
        #expect(await Router<Void>.empty.handle.runReader(())(req(.GET, "/anything")).run().response.status == .notFound)
    }

    @Test func matchesRegisteredRoute() async {
        let router = when(get("/ping") >=> ignoreBody() >=> handle { _ in .html("pong") })
        #expect(await router.handle.runReader(())(req(.GET, "/ping")).run().response.status == .ok)
    }

    @Test func returnsNotFoundForUnregisteredPath() async {
        let router = when(get("/ping") >=> ignoreBody() >=> handle { _ in .html("pong") })
        #expect(await router.handle.runReader(())(req(.GET, "/other")).run().response.status == .notFound)
    }

    @Test func matchesFirstMatchingRoute() async {
        let routerA = when(get("/a") >=> ignoreBody() >=> handle { _ in .html("A") })
        let routerB = when(get("/b") >=> ignoreBody() >=> handle { _ in .html("B") })
        let run = (routerA <|> routerB).handle.runReader(())
        #expect(String(data: (await run(req(.GET, "/a")).run()).response.body, encoding: .utf8) == "A")
        #expect(String(data: (await run(req(.GET, "/b")).run()).response.body, encoding: .utf8) == "B")
    }

    @Test func decodesURLParams() async {
        struct UserParams: Decodable { let id: String }
        final class Box: @unchecked Sendable { var value: String? }
        let box = Box()
        let router = when(
            get("/users/:id", params: UserParams.self)
            >=> ignoreBody()
            >=> handle { (typedReq: TypedRequest<UserParams, Empty, Empty>) -> Result<Response, ResponseError> in
                box.value = typedReq.urlParams.id
                return .html("ok")
            }
        )
        _ = await router.handle.runReader(())(req(.GET, "/users/42")).run()
        #expect(box.value == "42")
    }

    @Test func decodesBodyViaDecoder() async {
        struct Body: Decodable { let name: String }
        struct Resp: Codable { let echo: String }
        let router = when(
            post("/echo")
            >=> decodeBody(JSONDecoder().decoderResult(for: Body.self))
            >=> handle { typedReq in .json(Resp(echo: typedReq.body.name), encoder: JSONEncoder()) }
        )
        let response = await router.handle.runReader(())(req(.POST, "/echo", body: Data(#"{"name":"hello"}"#.utf8))).run().response
        let decoded  = try? JSONDecoder().decode(Resp.self, from: response.body)
        #expect(decoded?.echo == "hello")
    }

    @Test func asyncHandlerViaDeferredTask() async {
        let router = when(get("/async") >=> ignoreBody() >=> handle { _ in DeferredTask { .html("async") } })
        #expect(
            String(data: (await router.handle.runReader(())(req(.GET, "/async")).run()).response.body, encoding: .utf8) == "async"
        )
    }

    #if canImport(Combine)
    @Test func asyncHandlerViaCombinePublisher() async {
        let router = when(
            get("/pub")
            >=> ignoreBody()
            >=> handle { (_: TypedRequest<Empty, Empty, Empty>) in
                Just(Result<Response, ResponseError>.html("pub").response)
                    .setFailureType(to: ResponseError.self)
                    .eraseToAnyPublisher()
            }
        )
        #expect(
            String(data: (await router.handle.runReader(())(req(.GET, "/pub")).run()).response.body, encoding: .utf8) == "pub"
        )
    }
    #endif

    @Test func handlerReceivesEnvironment() async {
        struct Env: Sendable { let greeting: String }
        let router = when(
            get("/hello") >=> ignoreBody() >=> handle { _ in Reader { env in .html(env.greeting) } },
            injecting: Env.self
        )
        let response = await router.handle.runReader(Env(greeting: "hi there"))(req(.GET, "/hello")).run().response
        #expect(String(data: response.body, encoding: .utf8) == "hi there")
    }
}

// MARK: - NIOServer

@Suite("NIOServer")
struct NIOServerTests {
    @Test func startServer_returnsReaderOverEnv() {
        let reader: Reader<Void, Result<Void, Error>> = startServer(port: 0, router: Router<Void>.empty)
        let _: (()) -> Result<Void, Error> = reader.runReader
        #expect(Bool(true))
    }

    // NIO's syncShutdownGracefully can hang on Linux even for a failed bind; skip all
    // tests that call runReader (and thus spin up an EventLoopGroup) on Linux.
    #if !os(Linux)
    @Test func startServer_failsOnOutOfRangePort() {
        #expect(startServer(host: "127.0.0.1", port: 99_999, router: Router<Void>.empty).runReader(()).isFailure)
    }

    // URLSession on Linux (FoundationNetworking) ignores timeoutInterval and hangs forever;
    // Swift Testing's .timeLimit is also not enforced on Linux.
    @Test(.timeLimit(.minutes(1)))
    func startServer_respondsToRequest() async throws {
        let port = 18_091
        let frozenRouter = when(
            get("/hello") >=> ignoreBody() >=> handle { req in .html("OK:\(req.raw.path)") }
        )
        Thread.detachNewThread {
            _ = startServer(port: port, router: frozenRouter).runReader(())
        }
        try await Task.sleep(for: .milliseconds(300))

        // swiftlint:disable:next force_unwrapping
        var urlRequest = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/hello")!)
        urlRequest.timeoutInterval = 5
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(data: data, encoding: .utf8) == "OK:/hello")
    }

    @Test(.timeLimit(.minutes(1)))
    func startServer_routesRequests() async throws {
        let port = 18_092
        struct EchoBody: Decodable { let message: String }
        struct EchoResp: Codable { let message: String }

        let frozenRouter =
            when(get("/ping") >=> ignoreBody() >=> handle { _ in .html("pong") })
            <|> when(
                post("/echo")
                >=> decodeBody(JSONDecoder().decoderResult(for: EchoBody.self))
                >=> handle { req in .json(EchoResp(message: req.body.message), encoder: JSONEncoder()) }
            )
        Thread.detachNewThread {
            _ = startServer(port: port, router: frozenRouter).runReader(())
        }
        try await Task.sleep(for: .milliseconds(300))

        // swiftlint:disable:next force_unwrapping
        let (pingData, pingResp) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/ping")!)
        #expect((pingResp as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(data: pingData, encoding: .utf8) == "pong")

        // swiftlint:disable:next force_unwrapping
        var echoReq = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/echo")!)
        echoReq.httpMethod = "POST"
        echoReq.httpBody   = Data(#"{"message":"hello"}"#.utf8)
        let (echoData, _)  = try await URLSession.shared.data(for: echoReq)
        #expect(try JSONDecoder().decode(EchoResp.self, from: echoData).message == "hello")

        // swiftlint:disable:next force_unwrapping
        let (_, notFoundResp) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/missing")!)
        #expect((notFoundResp as? HTTPURLResponse)?.statusCode == 404)
    }
    #endif
}
