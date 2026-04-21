# NetworkTools

A suite of Swift packages for HTML templating, HTTP client networking, and HTTP server hosting. Built on functional programming principles using [`FP`](https://github.com/luizmb/FP): every public API uses `Reader` for dependency injection, `Result` for error handling, `DeferredTask` / `Publisher` (Combine) for async work, and `FunctionWrapper` for composable function types. No force-unwraps, no `fatalError`, no silent failures.

**Platforms:** macOS 13+, iOS 16+, tvOS 16+, watchOS 9+

---

## Packages

- [HTMLTemplating](#htmltemplating) — file-based HTML template engine with `{{}}` directives
- [NetworkClient](#networkclient) — composable HTTP client built on `URLSession` and Combine
- [NetworkServer](#networkserver) — embedded NIO-backed HTTP server with a typed functional routing DSL

---

## Installation

```swift
// Package.swift
.package(url: "https://github.com/luizmb/NetworkTools.git", branch: "main")
```

Add individual products to your targets as needed:

```swift
.product(name: "HTMLTemplating", package: "NetworkTools"),
.product(name: "NetworkClient",  package: "NetworkTools"),
.product(name: "NetworkServer",  package: "NetworkTools"),
```

---

## HTMLTemplating

A lightweight template engine that resolves `{{variables}}`, loops, conditionals, and includes. The fragment directory is threaded as a `Reader` environment — no stored properties, no singletons.

### Core types

```swift
public struct HTMLEnvironment {
    // Resolves a filename to a URL, or nil if not found.
    // All files use the .template extension: find("row.template") for fragments,
    // find("index.template") for top-level templates.
    public let find: (String) -> URL?
    // Reads a URL's contents, returning an error on failure.
    public let readFile: (URL) -> Result<String, Error>

    // Designated init — supply both for fully custom behaviour.
    public init(find: @escaping (String) -> URL?, readFile: @escaping (URL) -> Result<String, Error>)

    // Direct filesystem: appends the filename to path, reads via String(contentsOf:encoding:).
    public static func live(path: String) -> Self

    // Bundle-based: calls Bundle.url(forResource:withExtension:"template"),
    // reads via String(contentsOf:encoding:).
    public static func live(bundle: Bundle) -> Self

    // Testing: find returns a synthetic URL, readFile always succeeds with the given string.
    public static func mockSuccess(contents: String) -> Self

    // Testing: find returns a synthetic URL, readFile always fails with the given error.
    public static func mockFailure(error: Error) -> Self
}
```

All IO flows through the environment. Neither `render` nor `loadTemplate` performs IO directly.

```swift
// A template context: keys map to strings, booleans, or lists of sub-contexts.
public typealias Context = [String: TemplateValue]

public indirect enum TemplateValue {
    case string(String)
    case bool(Bool)
    case list([Context])
}

public enum TemplateError: Error {
    case notFound(String)           // template/fragment file not found
    case readError(String, Error)   // I/O error reading the file
}
```

### `render`

```swift
func render(_ template: String, _ context: Context) -> Reader<HTMLEnvironment, Result<String, TemplateError>>
```

The entry point. Returns a `Reader` that must be run with an `HTMLEnvironment` to produce a `Result<String, TemplateError>`.

```swift
let env = HTMLEnvironment.live(path: "/path/to/templates")

let result = render("Hello, {{name}}!", ["name": .string("World")])
    .runReader(env)

// result == .success("Hello, World!")
```

### Variable substitution — `{{key}}`

Replaced with the string value of the key, or an empty string if the key is missing or is a list.

```swift
let template = "<title>{{title}}</title><p>{{body}}</p>"
let ctx: Context = [
    "title": .string("My Page"),
    "body":  .string("Welcome!"),
]
let html = try render(template, ctx).runReader(env).get()
// "<title>My Page</title><p>Welcome!</p>"
```

Booleans render as `"true"` or `"false"`:

```swift
render("Active: {{active}}", ["active": .bool(true)]).runReader(env)
// .success("Active: true")
```

### Loops — `{{#each key fragmentName}}`

Renders a fragment file once per item in a list, giving each iteration its own isolated sub-context.

```swift
// fragments/row.html.template:
// <li>{{name}} — {{score}}</li>

let ctx: Context = [
    "players": .list([
        ["name": .string("Alice"), "score": .string("42")],
        ["name": .string("Bob"),   "score": .string("37")],
    ])
]

let template = "<ul>{{#each players row}}</ul>"
let html = try render(template, ctx).runReader(env).get()
// "<ul><li>Alice — 42</li><li>Bob — 37</li></ul>"
```

An empty list produces no output; a missing key is silently skipped.

### Conditionals — `{{#if key fragmentName}}`

Renders a fragment if the key is truthy (non-empty string, `true`, or non-empty list).

```swift
// fragments/badge.html.template:
// <span class="admin">Admin</span>

let template = "<p>{{username}}{{#if isAdmin badge}}</p>"
let ctx: Context = [
    "username": .string("alice"),
    "isAdmin":  .bool(true),
]
let html = try render(template, ctx).runReader(env).get()
// "<p>alice<span class=\"admin\">Admin</span></p>"
```

Falsy values (empty string, `false`, empty list, missing key) produce no output.

### Includes — `{{#include fragmentName}}`

Inserts another fragment file inline, passing the current context through.

```swift
// fragments/header.html.template:
// <header><h1>{{siteName}}</h1></header>

// fragments/footer.html.template:
// <footer>© {{year}}</footer>

let template = """
{{#include header}}
<main>{{content}}</main>
{{#include footer}}
"""
let ctx: Context = [
    "siteName": .string("My App"),
    "content":  .string("<p>Hello</p>"),
    "year":     .string("2025"),
]
let html = try render(template, ctx).runReader(env).get()
```

Includes compose freely — a fragment can itself contain `#include`, `#each`, and `#if` directives. Errors propagate outward through the `Result`.

### HTML escaping

```swift
esc("<script>alert('xss')</script>")
// "&lt;script&gt;alert('xss')&lt;/script&gt;"

escAttr(#"say "hello""#)
// "say &quot;hello&quot;"
```

`esc` escapes `&`, `<`, `>`. `escAttr` additionally escapes `"` for use inside HTML attributes.

### Template loader

`loadTemplate` reads a named `.template` file via the environment and returns a `Reader` just like `render`. Compose them with `flatMap` so the environment is injected once:

```swift
let ctx: Context = ["title": .string("Home"), "body": .string("<p>Hello</p>")]

// >>- is the ReaderTResult bind: threads the Result error automatically.
let page = loadTemplate("index") >>- { source in render(source, ctx) }

// Direct filesystem:
let html = page.runReader(.live(path: "/app/templates"))

// Bundle:
let html = page.runReader(.live(bundle: .main))

// Testing — no filesystem, no bundle:
let html = page.runReader(.mockSuccess(contents: "<p>{{body}}</p>"))
```

### Composing with Reader

Because `render` returns a `Reader`, you can swap the environment entirely without touching the template logic:

```swift
let pageReader: Reader<HTMLEnvironment, Result<String, TemplateError>> =
    render("{{#include layout}}", [
        "title":   .string("Dashboard"),
        "content": .string(bodyHTML),
    ])

// Production: filesystem-based.
let prodHTML = pageReader.runReader(.live(path: "/app/templates"))
// Or bundle-based:
// let prodHTML = pageReader.runReader(.live(bundle: .main))

// Testing: every fragment load succeeds with a fixed string.
let testHTML = pageReader.runReader(.mockSuccess(contents: "<html>{{content}}</html>"))

// Testing: every fragment load fails — verifies error propagation.
let failHTML = pageReader.runReader(.mockFailure(error: URLError(.fileDoesNotExist)))
```

All IO is fully contained in the environment — `render` never touches the filesystem directly.

---

## NetworkClient

A composable HTTP client. The core type `RequestPublisher<A>` is a `FunctionWrapper` around `(URLRequest) -> AnyPublisher<A, HTTPError>`, forming a Reader + Publisher monad stack. Every step in a request pipeline — sending, validating, decoding — is a composable value.

> **Note:** `NetworkClient` requires Combine and is available on macOS 10.15+, iOS 13+, tvOS 13+, watchOS 6+.

### Core types

```swift
// The primary type: a reusable function from URLRequest to a typed response publisher.
public struct RequestPublisher<A>: FunctionWrapper

// Alias for the raw response pair before status/decoding.
public typealias Requester = RequestPublisher<(Data, HTTPURLResponse)>

// A reusable decoding function: Data -> Result<D, DecodingError>.
public struct DecoderResult<D>: FunctionWrapper

public enum HTTPError: Error {
    case network(Error)         // URLSession-level failure
    case badStatus(Int, Data)   // non-2xx response (code + raw body for diagnostics)
    case decoding(Error)        // JSON decoding failure
}
```

### Making requests

`URLSession` gains a `.requester` property that lifts `dataTaskPublisher` into a `Requester`:

```swift
let requester: Requester = URLSession.shared.requester
```

Call it with any `URLRequest` to get a publisher:

```swift
// swiftlint:disable:next force_unwrapping
let url = URL(string: "https://api.example.com/users/1")!
let publisher: AnyPublisher<(Data, HTTPURLResponse), HTTPError> =
    requester(URLRequest(url: url))
```

### Full pipeline: validate → decode

```swift
struct User: Decodable {
    let id: Int
    let name: String
}

// Build a reusable typed pipeline; run it with a URLRequest when needed.
let getUser: RequestPublisher<User> =
    URLSession.shared.requester
        .validateStatusCode()
        .decode(User.self, decoder: JSONDecoder().decoderResult(for: User.self).run)

// swiftlint:disable:next force_unwrapping
let request = URLRequest(url: URL(string: "https://api.example.com/users/1")!)
getUser(request)
    .sink(
        receiveCompletion: { print("done:", $0) },
        receiveValue:      { print("user:", $0.name) }
    )
```

### `DecoderResult` — reusable decoders

`DecoderResult<D>` is a `FunctionWrapper<Data, Result<D, DecodingError>>`. A `JSONDecoder` produces one via `decoderResult(for:)`:

```swift
let decoder = JSONDecoder()
decoder.keyDecodingStrategy = .convertFromSnakeCase

let userDecoder: DecoderResult<User> = decoder.decoderResult(for: User.self)

// Use directly:
let result: Result<User, DecodingError> = userDecoder(jsonData)

// Post-process with map to extract a field:
let nameDecoder: DecoderResult<String> = userDecoder.map(\.name)
```

`DecoderResult` supports the full Functor / Applicative / Monad hierarchy.

### Functor — transforming responses

`map` transforms the decoded output of a successful publisher:

```swift
// Get just the name from a user endpoint.
let namePublisher: RequestPublisher<String> =
    URLSession.shared.requester
        .validateStatusCode()
        .decode(User.self, decoder: userDecoder.run)
        .map(\.name)

// Using the <£> (fmap) operator — function on the left:
let namePublisher2: RequestPublisher<String> =
    \.name <£> URLSession.shared.requester
        .validateStatusCode()
        .decode(User.self, decoder: userDecoder.run)
```

### Applicative — combining independent requests

`apply` (or `<*>`) runs two `RequestPublisher`s against the same `URLRequest` and zips their results:

```swift
struct Dashboard { let user: User; let stats: Stats }

// Lift the constructor into a publisher, then apply each field independently.
let dashboardPublisher: RequestPublisher<Dashboard> =
    RequestPublisher.pure(curry(Dashboard.init))
    <*> URLSession.shared.requester.validateStatusCode().decode(User.self,  decoder: userDecoder.run)
    <*> URLSession.shared.requester.validateStatusCode().decode(Stats.self, decoder: statsDecoder.run)
```

### Monad — chaining dependent requests

`flatMap` (or `>>-`) threads the same base `URLRequest` through a dependent chain:

```swift
// Fetch a user, then fetch their team using the team ID from the first response.
let userAndTeam: RequestPublisher<(User, Team)> =
    URLSession.shared.requester
        .validateStatusCode()
        .decode(User.self, decoder: userDecoder.run)
        >>- { user in
            // swiftlint:disable:next force_unwrapping
            let teamURL = URL(string: "https://api.example.com/teams/\(user.teamId)")!
            return URLSession.shared.requester
                .validateStatusCode()
                .decode(Team.self, decoder: teamDecoder.run)
                .map { (user, $0) }
        }
```

### Kleisli composition — point-free pipelines

Kleisli composition (`>=>`) sequences functions of the form `(A) -> RequestPublisher<B>`:

```swift
let fetchUser:    (Int)  -> RequestPublisher<User>    = { id in ... }
let fetchTeam:    (User) -> RequestPublisher<Team>    = { user in ... }
let fetchProject: (Team) -> RequestPublisher<Project> = { team in ... }

// Compose into a single (Int) -> RequestPublisher<Project>:
let fetchProjectForUser: (Int) -> RequestPublisher<Project> =
    fetchUser >=> fetchTeam >=> fetchProject

// swiftlint:disable:next force_unwrapping
fetchProjectForUser(42)(URLRequest(url: URL(string: "https://api.example.com")!))
    .sink(receiveCompletion: { _ in }, receiveValue: { print($0) })
```

### Error recovery

```swift
let resilient: RequestPublisher<User> =
    URLSession.shared.requester
        .validateStatusCode()
        .decode(User.self, decoder: userDecoder.run)
        .flatMapError { _ in RequestPublisher.pure(User.guest) }
```

### Operator reference

| Operator | Meaning |
|----------|---------|
| `f <£> r` | `fmap`: apply `f` to the output of `r` |
| `r <&> f` | flipped `fmap` |
| `r £> v`  | replace output with constant `v` |
| `f <*> r` | `apply`: function-in-publisher applied to value-in-publisher |
| `a *> b`  | sequence, keep right |
| `a <* b`  | sequence, keep left |
| `r >>- f` | `bind`: flatMap (`r` then `f`) |
| `f -<< r` | flipped bind |
| `f >=> g` | Kleisli left-to-right composition |
| `g <=< f` | Kleisli right-to-left composition |

---

## NetworkServer

An embedded HTTP server backed by SwiftNIO. Routes are built by Kleisli-composing (`>=>`) a series of lifting functions, then wrapping the result with `when(…)`. Routers are values — they combine with `<|>`, transform their environment with `pullback`, and are injected into the server via `Reader`.

### Mental model

```
get(path, params:, query:)    — GET route entry point
post / put / patch / delete   — other HTTP verbs; same signature

>=> ignoreBody()              — no body; imposes no Decodable constraint
 or decodeBody(decoder)       — decode body as B (requires B: Decodable)

>=> handle { req in … }       — lift closure into Reader<Env, DeferredTask<Result<Response, ResponseError>>>

when(chain)                   — wrap into Router<Void>
when(chain, injecting: T.self) — wrap into Router<T> for non-Void environments
```

Multiple routers combine with `<|>`. The operator tries the left router first and falls through to the right only on a 404 (unmatched route). Query-param errors (400) and body-decode errors (400) stop immediately without trying the next router.

The environment is injected **once at startup** via `runReader`. Every `>=>` step and every call to `handle` is pure — no side effects, no env access — until `startServer(…).runReader(env)` is called.

### Core types

```swift
// A route pattern with typed URL and query parameter structs.
// Use Empty for parameter groups that require no decoding.
public struct Route<URLParams: Decodable, QueryParams: Decodable>: Sendable

// A first-class router value. Its handle property is a Reader — inject the
// environment once at startup via handle.runReader(env) to get the request handler.
public struct Router<Env: Sendable>

// A fully decoded, typed request passed to every handler.
public struct TypedRequest<URLParams, QueryParams, Body> {
    public let urlParams:   URLParams
    public let queryParams: QueryParams
    public let body:        Body
    public let raw:         Request     // original NIO request (method, uri, path, body, queryParams)
}

// Encodes a value T into a Result<Response, ResponseError>.
public struct ResponseEncoder<T>

// Typed error value; the response status code, headers, and body are all fields.
public struct ResponseError: Error {
    public let status:  HTTPResponseStatus
    public let headers: [(String, String)]
    public let body:    Data
}

// Sentinel for any type parameter that carries no data.
public struct Empty: Codable, Sendable {
    public static let value: Empty
}
```

### Starting a server

```swift
// startServer returns a Reader — inject the environment when running.
// This call blocks until the server shuts down (or fails to bind).
let result: Result<Void, Error> = startServer(port: 8080, router: myRouter).runReader(myEnv)

// Run on a background thread to avoid blocking the caller:
Thread.detachNewThread {
    _ = startServer(port: 8080, router: myRouter).runReader(myEnv)
}
```

### Minimal example

```swift
let router = when(
    get("/ping") >=> ignoreBody() >=> handle { _ in .html("pong") }
)

Thread.detachNewThread {
    _ = startServer(port: 8080, router: router).runReader(())
}
```

### Typed URL parameters

Declare a `Decodable` struct whose property names match the `:placeholder` names in the route pattern. `URLParamsDecoder` maps path segments to struct fields using their string values.

```swift
struct AlbumID: Decodable { let id: String }

let router = when(
    get("/albums/:id", params: AlbumID.self)
    >=> ignoreBody()
    >=> handle { req in .html("Album: \(req.urlParams.id)") }
)
```

Multiple parameters work the same way — one struct field per placeholder:

```swift
struct PhotoPath: Decodable {
    let albumId: String
    let photoId: String
}

let router = when(
    get("/albums/:albumId/photos/:photoId", params: PhotoPath.self)
    >=> ignoreBody()
    >=> handle { req in .html("Album \(req.urlParams.albumId), photo \(req.urlParams.photoId)") }
)
```

Typed URL params participate in routing. If a `:placeholder` cannot be decoded into the declared Swift type (e.g., a field typed as `Int` when the path segment is `"beach"`), the route returns 404 and the next router is tried. This lets the same URL shape be handled by different typed routes:

```swift
struct NumericID: Decodable { let id: Int }
struct StringSlug: Decodable { let id: String }

// GET /albums/123  → matched by Int route  → "Numeric album: 123"
// GET /albums/jazz → falls through (404)   → matched by String route → "Album slug: jazz"
let router =
    when(get("/albums/:id", params: NumericID.self) >=> ignoreBody()
         >=> handle { req in .html("Numeric album: \(req.urlParams.id)") })
    <|> when(get("/albums/:id", params: StringSlug.self) >=> ignoreBody()
             >=> handle { req in .html("Album slug: \(req.urlParams.id)") })
```

### Typed query parameters

Declare a `Decodable` struct whose fields match the query-string keys. Optional fields are accepted even when the key is absent; required fields that are missing cause a 400 response.

```swift
struct Pagination: Decodable {
    let page:  Int?
    let limit: Int?
}

// GET /items?page=2&limit=20
let router = when(
    get("/items", query: Pagination.self)
    >=> ignoreBody()
    >=> handle { req in
        let page  = req.queryParams.page  ?? 1
        let limit = req.queryParams.limit ?? 10
        return .plainText("page=\(page) limit=\(limit)")
    }
)
```

### Returning JSON

Use `ResponseEncoder<T>.json` — it is a `Reader<EncoderResultFactory, ResponseEncoder<T>>`, so inject a factory (any `EncoderResultFactory`, e.g. a `JSONEncoder`) directly to materialise it:

```swift
struct Album: Codable {
    let id:    Int
    let title: String
}

// Define encoders once and reuse them across handlers.
let albumEncoder: ResponseEncoder<Album> = .json.runReader(JSONEncoder())

let router = when(
    get("/albums/1")
    >=> ignoreBody()
    >=> handle { _ in albumEncoder.response(Album(id: 1, title: "Kind of Blue")) }
)
```

Configure the `JSONEncoder` before injecting it:

```swift
let prettyEncoder: JSONEncoder = {
    let e = JSONEncoder()
    e.outputFormatting  = [.prettyPrinted, .sortedKeys]
    e.keyEncodingStrategy = .convertToSnakeCase
    return e
}()

let albumEncoder: ResponseEncoder<Album> = .json.runReader(prettyEncoder)
```

### Body decoding

Use `decodeBody(decoder)` as the middle step in the Kleisli chain. It runs the decoder only when the route matches; a decode failure returns 400 before the handler is called. Unlike `ignoreBody()`, it requires `B: Decodable`.

```swift
struct CreateAlbum: Decodable { let title: String }
struct Album:       Codable   { let id: Int; let title: String }

let albumDecoder: DecoderResult<CreateAlbum> = JSONDecoder().decoderResult(for: CreateAlbum.self)
let albumEncoder: ResponseEncoder<Album>     = .json.runReader(JSONEncoder())

let router = when(
    post("/albums")
    >=> decodeBody(albumDecoder)
    >=> handle { req in albumEncoder.response(Album(id: nextID(), title: req.body.title), status: .created) }
)
```

Combine URL params, query params, and a body in one route:

```swift
struct AlbumID:     Decodable { let id: Int }
struct Format:      Decodable { let format: String? }
struct CreatePhoto: Decodable { let caption: String; let data: String }

let router = when(
    post("/albums/:id/photos", params: AlbumID.self, query: Format.self)
    >=> decodeBody(JSONDecoder().decoderResult(for: CreatePhoto.self))
    >=> handle { req in
        .html("Uploaded to album \(req.urlParams.id) as \(req.queryParams.format ?? "jpeg")")
    }
)
```

### Combining routers

`<|>` is the ordered-choice operator for routers. It tries the left side first; it falls through to the right only when the left returns 404.

```swift
let router: Router<Void> =
    when(get("/ping")   >=> ignoreBody() >=> handle { _ in .html("pong") })
    <|> when(get("/health") >=> ignoreBody() >=> handle { _ in .html("ok") })
    <|> when(
        post("/echo")
        >=> decodeBody(JSONDecoder().decoderResult(for: [String: String].self))
        >=> handle { req in
            .from(encoder: JSONEncoder(), entity: req.body)
        }
    )
```

`Router.empty` is the identity — a router that always returns 404:

```swift
let empty = Router<Void>.empty
// empty.handle.runReader(())(request) always yields .failure(.notFound)
```

### `handle` — lifting closure variants

`handle` is a free function that lifts any of several closure shapes into the Kleisli step `(TypedRequest<U,Q,B>) -> Reader<Env, DeferredTask<Result<Response, ResponseError>>>`:

```swift
// Sync — returns Response
handle { req -> Response in Response(status: .ok) }

// Sync failable — returns Result<Response, ResponseError>
handle { req -> Result<Response, ResponseError> in
    guard req.urlParams.id > 0 else { return .badRequest("id must be positive") }
    return albumEncoder.response(myAlbum)
}

// Sync throwing — typed throws(ResponseError)
handle { req throws(ResponseError) -> Response in
    guard let album = find(req.urlParams.id) else { throw .notFound }
    return try albumEncoder.response(album).get()
}

// Async — returns DeferredTask<Response>
handle { req in DeferredTask { await fetchAlbum(req.urlParams.id) } }

// Async failable — returns DeferredTask<Result<Response, ResponseError>>
handle { req in
    DeferredTask {
        guard let album = await db.fetchAlbum(req.urlParams.id) else { return .notFound }
        return albumEncoder.response(album)
    }
}
```

### Environment-dependent handlers

When the handler needs values from the server's environment (database connections, config, auth tokens), return a `Reader` from the closure. `Env` is only constrained by what your closure returns — no protocol conformance required by `ignoreBody` or `decodeBody` themselves.

```swift
struct AppEnv: Sendable {
    let db:     Database
    let config: Config
}

struct AlbumID: Decodable { let id: Int }

let router: Router<AppEnv> = when(
    get("/albums/:id", params: AlbumID.self)
    >=> ignoreBody()
    >=> handle { req in
        Reader { env in
            DeferredTask {
                guard let album = await env.db.fetchAlbum(id: req.urlParams.id) else {
                    return .notFound
                }
                return albumEncoder.response(album)
            }
        }
    },
    injecting: AppEnv.self
)

// Inject the environment at startup, not at route definition time.
startServer(port: 8080, router: router).runReader(AppEnv(db: db, config: config))
```

For synchronous env access:

```swift
struct ConfigEnv: Sendable { let greeting: String }

let router: Router<ConfigEnv> = when(
    get("/hello")
    >=> ignoreBody()
    >=> handle { _ in Reader { env in .html(env.greeting) } },
    injecting: ConfigEnv.self
)

startServer(port: 8080, router: router).runReader(ConfigEnv(greeting: "Hi there!"))
```

### `pullback` — composing routers with different environments

`pullback` adapts a `Router<SmallEnv>` to work inside a larger environment by providing a function `(World) -> SmallEnv`. This lets you build modular routers that know only about their own slice of the environment, then assemble them at the top level:

```swift
struct AppEnv: Sendable {
    let auth: AuthEnv
    let data: DataEnv
}

// Each sub-module declares only what it needs.
let authRouter: Router<AuthEnv> = /* login/logout routes */
let dataRouter: Router<DataEnv> = /* resource routes */

// Combine at the app level, mapping each router to its env slice.
let appRouter: Router<AppEnv> =
    authRouter.pullback(\.auth)
    <|> dataRouter.pullback(\.data)

startServer(port: 8080, router: appRouter).runReader(AppEnv(auth: authEnv, data: dataEnv))
```

### `ResponseEncoder` reference

```swift
// HTML — wraps a String in text/html; charset=utf-8
ResponseEncoder<String>.html.response("Hello")              // Result<Response, ResponseError>
ResponseEncoder<String>.html.response("<b>bad</b>", status: .badRequest)

// Plain text
ResponseEncoder<String>.plainText.response("OK")

// JSON — inject any EncoderResultFactory (e.g. JSONEncoder) directly
let enc: ResponseEncoder<MyType> = .json.runReader(JSONEncoder())
enc.response(value)              // 200
enc.response(value, status: .created) // 201

// Raw bytes — passes Data through unchanged (application/octet-stream)
ResponseEncoder<Data>.raw.response(pdfData)

// Image — defaults to image/jpeg; specify mimeType for others
ResponseEncoder<Data>.image().response(jpegData)
ResponseEncoder<Data>.image(mimeType: "image/png").response(pngData)

// Calling as a function — returns just the Data (no Response wrapper)
let data: Result<Data, EncodingError> = enc(value)
```

### `Result<Response, ResponseError>` factories

Handlers return `Result<Response, ResponseError>`. Static factories let you construct these with leading-dot syntax:

```swift
// Success
.from(encoder: JSONEncoder(), entity: album)              // 200 application/json
.from(encoder: JSONEncoder(), entity: album, status: .created)
.html("<h1>Hello</h1>")                                   // 200 text/html
.html("<b>bad</b>", status: .badRequest)
.plainText("OK")
.raw(pdfData)

// Failure
.notFound                                                 // 404
.badRequest("missing 'title'")                            // 400
.serverError("db unavailable")                            // 500
```

Pre-configure a `ResponseEncoder` once and call `.response` on it when you need more control (custom content type, image, re-use across handlers):

```swift
let albumEncoder: ResponseEncoder<Album> = .json.runReader(JSONEncoder())
albumEncoder.response(album)                              // 200
albumEncoder.response(album, status: .created)            // 201
```

### `ResponseError` reference

```swift
ResponseError.notFound                          // 404 text/plain "Not Found"
ResponseError.badRequest("missing 'title'")     // 400 text/plain
ResponseError.serverError("db unavailable")     // 500 text/plain

// Custom status/headers/body
ResponseError(status: .unauthorized, headers: [("WWW-Authenticate", "Bearer")], body: Data())

// Encoded body — use any ResponseEncoder
ResponseError(Payload(code: 42), encoder: enc, status: .unprocessableEntity)
```

### Full example: mini albums API

```swift
import Foundation
import NIOHTTP1
import NetworkServer

// MARK: - Models

struct Album: Codable, Sendable {
    let id:    Int
    let title: String
    let year:  Int
}

struct CreateAlbum: Decodable { let title: String; let year: Int }

// MARK: - Environment

struct AppEnv: Sendable {
    var albums: [Album]

    static let live = AppEnv(albums: [
        Album(id: 1, title: "Kind of Blue",    year: 1959),
        Album(id: 2, title: "A Love Supreme",  year: 1964),
        Album(id: 3, title: "In a Silent Way", year: 1969),
    ])
}

// MARK: - Encoders / Decoders

let albumEncoder:  ResponseEncoder<Album>     = .json.runReader(JSONEncoder())
let albumsEncoder: ResponseEncoder<[Album]>   = .json.runReader(JSONEncoder())
let albumDecoder:  DecoderResult<CreateAlbum> = JSONDecoder().decoderResult(for: CreateAlbum.self)

// MARK: - Route params

struct AlbumID:   Decodable { let id:   Int }
struct YearQuery: Decodable { let year: Int? }

// MARK: - Router

let router: Router<AppEnv> =

    // GET /albums — list all, optionally filtered by ?year=
    when(
        get("/albums", query: YearQuery.self)
        >=> ignoreBody()
        >=> handle { req in
            Reader { env -> Result<Response, ResponseError> in
                let albums = req.queryParams.year.map { y in env.albums.filter { $0.year == y } }
                             ?? env.albums
                return albumsEncoder.response(albums)
            }
        },
        injecting: AppEnv.self
    )

    // GET /albums/:id — fetch one album by integer ID
    <|> when(
        get("/albums/:id", params: AlbumID.self)
        >=> ignoreBody()
        >=> handle { req in
            Reader { env -> Result<Response, ResponseError> in
                guard let album = env.albums.first(where: { $0.id == req.urlParams.id }) else {
                    return .notFound
                }
                return albumEncoder.response(album)
            }
        },
        injecting: AppEnv.self
    )

    // POST /albums — create a new album from a JSON body
    <|> when(
        post("/albums")
        >=> decodeBody(albumDecoder)
        >=> handle { req in
            Reader { env -> Result<Response, ResponseError> in
                let newAlbum = Album(id: env.albums.count + 1, title: req.body.title, year: req.body.year)
                return albumEncoder.response(newAlbum, status: .created)
            }
        },
        injecting: AppEnv.self
    )

// MARK: - Start

Thread.detachNewThread {
    _ = startServer(port: 8080, router: router).runReader(.live)
}
```

### Integrating with HTMLTemplating

`NetworkServer` and `HTMLTemplating` compose naturally — run the `Reader` from `render` inside an env-aware handler:

```swift
struct WebEnv: Sendable {
    let templates: HTMLEnvironment
    let db: Database
}

let router: Router<WebEnv> = when(
    get("/")
    >=> ignoreBody()
    >=> handle { _ in
        Reader { env -> Result<Response, ResponseError> in
            let ctx: Context = [
                "title":  .string("Albums"),
                "albums": .list(env.db.allAlbums().map { ["title": .string($0.title)] }),
            ]
            switch render("{{#include page}}", ctx).runReader(env.templates) {
            case .success(let html): return .html(html)
            case .failure(let err):  return .serverError(String(describing: err))
            }
        }
    },
    injecting: WebEnv.self
)

startServer(port: 8080, router: router).runReader(
    WebEnv(templates: .live(path: "/app/templates"), db: myDB)
)
```

---

## Design principles

All three packages follow the same functional conventions via [`FP`](https://github.com/luizmb/FP):

- **`Reader`** for dependency injection (template environment, server environment, request threading). No `init` injection, no stored globals.
- **`Result`** instead of `throws` at all public API boundaries. Errors are values.
- **`DeferredTask`** for async work in the server (lazy, nothing runs until `.run()` is called). **`Publisher`** (Combine) for the HTTP client (composable, cancellable, backpressure-aware).
- **`FunctionWrapper`** for any `(A) -> B` that should be composable — `RequestPublisher`, `DecoderResult`, `EncoderResult` all conform.
- **Alternative (`<|>`)** for router composition — tries left then right (only 404 falls through), identity is `Router.empty`.
- **No crashing operations** — no force-unwrap, no `fatalError`, no `try!`. All failure paths return `Result` or publisher errors.
