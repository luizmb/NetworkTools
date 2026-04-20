// swiftlint:disable file_length
import Core
import Foundation
import FP
import NIOHTTP1
import Testing
#if canImport(Combine)
import Combine
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

private func jsonEncoder<T: Encodable>(for type: T.Type = T.self, _ configure: (JSONEncoder) -> Void = { _ in }) -> ResponseEncoder<T> {
    let e = JSONEncoder()
    configure(e)
    return ResponseEncoder<T>.json.runReader(.json.runReader(e))
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
        let e = ResponseError(Payload(code: 42), encoder: jsonEncoder(), status: .unprocessableEntity)
        #expect(e.status == .unprocessableEntity)
        #expect(e.headers.contains { $0 == ("Content-Type", "application/json") })
        #expect(try JSONDecoder().decode(Payload.self, from: e.body).code == 42)
    }

    @Test func encodedHtml() {
        let e = ResponseError("<b>bad</b>", encoder: ResponseEncoder<String>.html, status: .badRequest)
        #expect(e.status == .badRequest)
        #expect(String(data: e.body, encoding: .utf8) == "<b>bad</b>")
    }
}

// MARK: - ResponseEncoder

@Suite("ResponseEncoder")
struct ResponseEncoderTests {
    @Test func html_encodesUTF8() throws {
        let r = try ResponseEncoder<String>.html.response("<h1>Hi</h1>").get()
        #expect(r.status == .ok)
        #expect(r.headers.contains { $0 == ("Content-Type", "text/html; charset=utf-8") })
        #expect(String(data: r.body, encoding: .utf8) == "<h1>Hi</h1>")
    }

    @Test func html_customStatus() throws {
        #expect(try ResponseEncoder<String>.html.response("x", status: .notFound).get().status == .notFound)
    }

    @Test func json_encodesValue() throws {
        struct Point: Codable { let x: Int; let y: Int }
        let r = try jsonEncoder(for: Point.self).response(Point(x: 1, y: 2)).get()
        #expect(r.status == .ok)
        #expect(r.headers.contains { $0 == ("Content-Type", "application/json") })
        let decoded = try JSONDecoder().decode(Point.self, from: r.body)
        #expect(decoded.x == 1 && decoded.y == 2)
    }

    @Test func json_customStatus() throws {
        struct S: Encodable { let k: String }
        #expect(try jsonEncoder(for: S.self).response(S(k: "v"), status: .created).get().status == .created)
    }

    @Test func json_sortedKeys() throws {
        let r = try jsonEncoder(for: [String: Int].self) { $0.outputFormatting = .sortedKeys }.response(["b": 2, "a": 1]).get()
        let raw = String(data: r.body, encoding: .utf8) ?? ""
        let aRange = try #require(raw.range(of: "\"a\""))
        let bRange = try #require(raw.range(of: "\"b\""))
        #expect(aRange.lowerBound < bRange.lowerBound)
    }

    @Test func raw_isIdentity() throws {
        let data = Data([0x01, 0x02, 0x03])
        #expect(try ResponseEncoder<Data>.raw.response(data).get().body == data)
    }

    @Test func image_jpeg() throws {
        let data = Data([0xFF, 0xD8])
        let r = try ResponseEncoder<Data>.image().response(data).get()
        #expect(r.status == .ok)
        #expect(r.headers.contains { $0 == ("Content-Type", "image/jpeg") })
        #expect(r.body == data)
    }

    @Test func image_customMimeType() throws {
        let r = try ResponseEncoder<Data>.image(mimeType: "image/png").response(Data()).get()
        #expect(r.headers.contains { $0 == ("Content-Type", "image/png") })
    }

    @Test func callAsFunction_returnsData() throws {
        let data = try ResponseEncoder<String>.html("hello").get()
        #expect(String(data: data, encoding: .utf8) == "hello")
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
        #expect(Route<Empty, Empty>(.GET, "/ping").match(req(.GET, "/ping")) != nil)
    }

    @Test func rejectsWrongMethod() {
        #expect(Route<Empty, Empty>(.GET, "/ping").match(req(.POST, "/ping")) == nil)
    }

    @Test func rejectsWrongPath() {
        #expect(Route<Empty, Empty>(.GET, "/ping").match(req(.GET, "/pong")) == nil)
    }

    @Test func decodesURLParams() {
        struct UserParams: Decodable { let id: String }
        let route = Route<UserParams, Empty>(.GET, "/users/:id")
        guard case .success(let mr) = route.match(req(.GET, "/users/42")) else {
            Issue.record("Expected .success"); return
        }
        #expect(mr.urlParams.id == "42")
    }

    @Test func returnsNilOnURLParamTypeMismatch() {
        struct UserParams: Decodable { let id: Int }
        #expect(Route<UserParams, Empty>(.GET, "/users/:id").match(req(.GET, "/users/abc")) == nil)
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
        #expect(Route<Empty, Q>(.GET, "/items").match(req(.GET, "/items")) != nil)
    }
}

// MARK: - Router

@Suite("Router")
struct RouterTests {
    private func req(_ method: HTTPMethod, _ uri: String, body: Data = Data()) -> Request {
        Request(method: method, uri: uri, body: body)
    }

    @Test func notFoundForEmptyRouter() async {
        #expect(await Router<Void>().handle(req(.GET, "/anything")).runReader(()).run().response.status == .notFound)
    }

    @Test func matchesRegisteredRoute() async {
        var router = Router<Void>()
        router.register(
            route: Route<Empty, Empty>(.GET, "/ping"),
            handler: .handle { _ in ResponseEncoder<String>.html.response("pong") }
        )
        #expect(await router.handle(req(.GET, "/ping")).runReader(()).run().response.status == .ok)
    }

    @Test func returnsNotFoundForUnregisteredPath() async {
        var router = Router<Void>()
        router.register(
            route: Route<Empty, Empty>(.GET, "/ping"),
            handler: .handle { _ in ResponseEncoder<String>.html.response("pong") }
        )
        #expect(await router.handle(req(.GET, "/other")).runReader(()).run().response.status == .notFound)
    }

    @Test func matchesFirstMatchingRoute() async {
        var router = Router<Void>()
        router.register(
            route: Route<Empty, Empty>(.GET, "/a"),
            handler: .handle { _ in ResponseEncoder<String>.html.response("A") }
        )
        router.register(
            route: Route<Empty, Empty>(.GET, "/b"),
            handler: .handle { _ in ResponseEncoder<String>.html.response("B") }
        )
        #expect(String(data: (await router.handle(req(.GET, "/a")).runReader(()).run()).response.body, encoding: .utf8) == "A")
        #expect(String(data: (await router.handle(req(.GET, "/b")).runReader(()).run()).response.body, encoding: .utf8) == "B")
    }

    @Test func decodesURLParams() async {
        struct UserParams: Decodable { let id: String }
        final class Box: @unchecked Sendable { var value: String? }
        let box = Box()
        var router = Router<Void>()
        router.register(
            route: Route<UserParams, Empty>(.GET, "/users/:id"),
            handler: .handle { (typedReq: TypedRequest<UserParams, Empty, Empty>) -> Result<Response, ResponseError> in
                box.value = typedReq.urlParams.id
                return ResponseEncoder<String>.html.response("ok")
            }
        )
        _ = await router.handle(req(.GET, "/users/42")).runReader(()).run()
        #expect(box.value == "42")
    }

    @Test func decodesBodyViaDecoder() async {
        struct Body: Decodable { let name: String }
        struct Resp: Codable { let echo: String }
        var router = Router<Void>()
        router.register(
            route: Route<Empty, Empty>(.POST, "/echo"),
            bodyDecoder: DecoderResult<Body>.json.runReader(JSONDecoder()),
            handler: .handle { typedReq in jsonEncoder(for: Resp.self).response(Resp(echo: typedReq.body.name)) }
        )
        let response = await router.handle(req(.POST, "/echo", body: Data(#"{"name":"hello"}"#.utf8))).runReader(()).run().response
        let decoded  = try? JSONDecoder().decode(Resp.self, from: response.body)
        #expect(decoded?.echo == "hello")
    }

    @Test func asyncHandlerViaDeferredTask() async {
        var router = Router<Void>()
        router.register(
            route: Route<Empty, Empty>(.GET, "/async"),
            handler: .handle { _ in DeferredTask { ResponseEncoder<String>.html.response("async") } }
        )
        #expect(String(data: (await router.handle(req(.GET, "/async")).runReader(()).run()).response.body, encoding: .utf8) == "async")
    }

    #if canImport(Combine)
    @Test func asyncHandlerViaCombinePublisher() async {
        var router = Router<Void>()
        router.register(
            route: Route<Empty, Empty>(.GET, "/pub"),
            handler: .handle { _ in Just(ResponseEncoder<String>.html.response("pub").response).eraseToAnyPublisher() }
        )
        #expect(String(data: (await router.handle(req(.GET, "/pub")).runReader(()).run()).response.body, encoding: .utf8) == "pub")
    }
    #endif

    @Test func handlerReceivesEnvironment() async {
        struct Env: Sendable { let greeting: String }
        var router = Router<Env>()
        router.register(
            route: Route<Empty, Empty>(.GET, "/hello"),
            handler: .handle { _ in Reader { env in ResponseEncoder<String>.html.response(env.greeting) } }
        )
        let response = await router.handle(req(.GET, "/hello")).runReader(Env(greeting: "hi there")).run().response
        #expect(String(data: response.body, encoding: .utf8) == "hi there")
    }
}

// MARK: - NIOServer

@Suite("NIOServer")
struct NIOServerTests {
    @Test func startServer_returnsReaderOverEnv() {
        let reader: Reader<Void, Result<Void, Error>> = startServer(port: 0, router: Router())
        let _: (()) -> Result<Void, Error> = reader.runReader
        #expect(Bool(true))
    }

    @Test func startServer_failsOnOutOfRangePort() {
        #expect(startServer(host: "127.0.0.1", port: 99_999, router: Router()).runReader(()).isFailure)
    }

    @Test(.timeLimit(.minutes(1)))
    func startServer_respondsToRequest() async throws {
        let port = 18_091
        var router = Router<Void>()
        router.register(
            route: Route<Empty, Empty>(.GET, "/hello"),
            handler: .handle { req in ResponseEncoder<String>.html.response("OK:\(req.raw.path)") }
        )
        let frozenRouter = router
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

        var router = Router<Void>()
        router.register(
            route: Route<Empty, Empty>(.GET, "/ping"),
            handler: .handle { _ in ResponseEncoder<String>.html.response("pong") }
        )
        router.register(
            route: Route<Empty, Empty>(.POST, "/echo"),
            bodyDecoder: DecoderResult<EchoBody>.json.runReader(JSONDecoder()),
            handler: .handle { req in jsonEncoder(for: EchoResp.self).response(EchoResp(message: req.body.message)) }
        )
        let frozenRouter = router
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
}
