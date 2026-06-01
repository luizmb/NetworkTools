# NetworkTools

A suite of Swift packages for HTML templating, HTTP client networking, and HTTP server hosting. Built on functional programming principles using [`FP`](https://github.com/luizmb/FP): every public API uses `Reader` for dependency injection, `Result` for error handling, `DeferredTask` / `Publisher` (Combine) for async work, and `FunctionWrapper` for composable function types. No force-unwraps, no `fatalError`, no silent failures.

**Platforms:** macOS 13+, iOS 16+, tvOS 16+, watchOS 9+

---

## Packages

- [Core](#core) — codec layer, `DemandBuffer`, and Combine helpers shared by the other packages
- [HTMLTemplating](#htmltemplating) — file-based HTML template engine with `{{}}` directives
- [Multipeer](#multipeer) — `MultipeerConnectivity` wrapper exposing Combine and `DeferredTask`/`DeferredStream` APIs side by side
- [NetworkClient](#networkclient) — composable HTTP client built on `URLSession` and Combine
- [NetworkServer](#networkserver) — embedded NIO-backed HTTP server with a typed functional routing DSL
- [WebSocketClient](#websocketclient) — full-duplex WebSocket client with Combine (`WebSocket`) and async (`WebSocketConnection`) APIs
- [BonjourService](#bonjourservice) — Bonjour discovery and advertising with Combine publishers and `DeferredStream` on both sides

---

## Installation

```swift
// Package.swift
.package(url: "https://github.com/luizmb/NetworkTools.git", branch: "main")
```

Add individual products to your targets as needed:

```swift
.product(name: "Core",            package: "NetworkTools"),
.product(name: "HTMLTemplating",  package: "NetworkTools"),
.product(name: "NetworkClient",   package: "NetworkTools"),
.product(name: "NetworkServer",   package: "NetworkTools"),
.product(name: "WebSocketClient", package: "NetworkTools"),
.product(name: "BonjourService",  package: "NetworkTools"),
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

## Core

Shared building blocks used by all three packages — the codec layer (with its Combine extensions) and the `Convert` function-wrapper. The `Loading<Success, Failure>` lifecycle enum used to live here; it now lives in [FP's `DataStructure` module](https://github.com/luizmb/FP/blob/main/docs/types/Loading.md) (from `v1.7.0` onwards) so any project can use it. Add `import DataStructure` to access it.

### `Convert<Input, Output, Failure>`

`Convert<Input, Output, Failure>` is a `FunctionWrapper` around `(Input) -> Result<Output, Failure>`. It is a reusable, composable fallible conversion as a first-class value, supporting the full Functor / Applicative / Monad hierarchy.

Concrete typealiases pin the type parameters for common uses:

```swift
// Data -> Result<D, DecodingError>
public typealias DataDecoder<D: Decodable> = Convert<Data, D, DecodingError>

// I -> Result<Data, EncodingError>
public typealias DataEncoder<I: Encodable> = Convert<I, Data, EncodingError>

// [String: String] -> Result<D, DecodingError>  (used by NetworkServer routing)
public typealias DictionaryDecoder<D: Decodable> = Convert<[String: String], D, DecodingError>
```

```swift
let userDecoder: DataDecoder<User>   = JSONDecoder().dataDecoder(for: User.self)
let albumEncoder: DataEncoder<Album> = JSONEncoder().dataEncoder(for: Album.self)

// Call directly:
let result: Result<User, DecodingError>  = userDecoder(jsonData)
let encoded: Result<Data, EncodingError> = albumEncoder(myAlbum)
```

### `DataDecoderFactory` / `DataEncoderFactory`

Protocols satisfied by `JSONDecoder` / `JSONEncoder` (and any custom codec). They let you inject the codec as a dependency rather than constructing it inline.

```swift
func makeDecoder() -> DataDecoderFactory {
    let d = JSONDecoder()
    d.keyDecodingStrategy = .convertFromSnakeCase
    return d
}
```

### `AnyPublisher` — decoding (Combine)

Static factory that lifts a `Data` value into a typed decoded publisher, for use inside `flatMap` chains:

```swift
// AnyPublisher<User, DecodingError>
let pub: AnyPublisher<User, DecodingError> = .decoding(jsonData, using: JSONDecoder())

// With a pre-built DataDecoder:
let pub2 = AnyPublisher<User, DecodingError>.decoding(jsonData, using: userDecoder)
```

### `AnyPublisher` — encoding (Combine)

Instance methods that encode the publisher's `Encodable` output to `Data`.

```swift
// Upstream failure type == EncodingError — no mapping needed:
let dataPublisher: AnyPublisher<Data, EncodingError> =
    someAlbumPublisher.encode(using: JSONEncoder())

// Upstream failure type is different — lift EncodingError with mapError:
let dataPublisher2: AnyPublisher<Data, MyError> =
    someAlbumPublisher.encode(using: JSONEncoder(), mapError: MyError.encoding)

// Both overloads also accept a pre-built DataEncoder<Output>:
someAlbumPublisher.encode(using: albumEncoder)
someAlbumPublisher.encode(using: albumEncoder, mapError: MyError.encoding)
```

### `Convert` — contravariant functor

`contramap` maps over the *input* type, adapting a `Convert<Input, Output, Failure>` to accept a different input by pre-processing it before the conversion runs:

```swift
let userDecoder: DataDecoder<User> = JSONDecoder().dataDecoder(for: User.self)

// Adapt to accept String instead of Data:
let stringDecoder: Convert<String, User, DecodingError> =
    userDecoder.contramap { Data($0.utf8) }
```

### `AnyPublisher` — bridging to `DeferredTask` (Combine)

The bridge from Combine into `DeferredTask` lives in `FP` (`AnyPublisher.toDeferredTask()`), not in `Core` — `Core` simply re-exports `FP`. Two overloads:

```swift
// Infallible publisher — DeferredTask<Output?> (nil if the publisher
// completes without emitting):
let task: DeferredTask<Int?> = someIntPublisher.toDeferredTask()

// Failable publisher — DeferredTask<Result<Output, any Error>>:
//   value emitted          → .success(value)
//   publisher fails        → .failure(originalError) as any Error
//   completes with nothing → .failure(EmptyPublisherError())
let task: DeferredTask<Result<User, any Error>> = somePublisher.toDeferredTask()
```

The failure type widens to `any Error` so the bridge can synthesize `EmptyPublisherError` when a failable publisher completes without ever emitting. Callers needing the original typed failure back can downcast with `as?` inside `.mapError`.

## NetworkClient

A composable HTTP client with two parallel APIs: `RequestPublisher<A>` (Combine) and `NetworkTask<A>` (async/await). Both model the same abstraction — a `URLRequest` environment threaded through a typed result pipeline — using different concurrency primitives.

> **Note:** `RequestPublisher` and its operators require Combine (macOS 10.15+, iOS 13+, tvOS 13+, watchOS 6+). `NetworkTask` and `URLSession.taskRequester` use `DeferredTask` and are available on all supported platforms without Combine.

### Core types

```swift
// The primary type: a reusable function from URLRequest to a typed response publisher.
public struct RequestPublisher<A>: FunctionWrapper

// Alias for the raw response pair before status/decoding.
public typealias Requester = RequestPublisher<(Data, HTTPURLResponse)>

// A reusable fallible conversion function: Input -> Result<Output, Failure>.
public struct Convert<Input, Output, Failure: Error>: FunctionWrapper

// Specialised typealiases from Core:
public typealias DataDecoder<D: Decodable> = Convert<Data, D, DecodingError>
public typealias DataEncoder<E: Encodable> = Convert<E, Data, EncodingError>

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
        .decode(using: JSONDecoder())

// swiftlint:disable:next force_unwrapping
let request = URLRequest(url: URL(string: "https://api.example.com/users/1")!)
getUser(request)
    .sink(
        receiveCompletion: { print("done:", $0) },
        receiveValue:      { print("user:", $0.name) }
    )
```

### `DataDecoder` — reusable decoders

`DataDecoder<D>` is `Convert<Data, D, DecodingError>`. A `JSONDecoder` produces one via `dataDecoder(for:)`:

```swift
let decoder = JSONDecoder()
decoder.keyDecodingStrategy = .convertFromSnakeCase

let userDecoder: DataDecoder<User> = decoder.dataDecoder(for: User.self)

// Use directly:
let result: Result<User, DecodingError> = userDecoder(jsonData)

// Post-process with map to extract a field:
let nameDecoder: DataDecoder<String> = userDecoder.map(\.name)
```

`DataDecoder` (and `Convert` in general) supports the full Functor / Applicative / Monad hierarchy.

### Functor — transforming responses

`map` transforms the decoded output of a successful publisher:

```swift
// Get just the name from a user endpoint.
let namePublisher: RequestPublisher<String> =
    URLSession.shared.requester
        .validateStatusCode()
        .decode(using: userDecoder)
        .map(\.name)

// Using the <£> (fmap) operator — function on the left:
let namePublisher2: RequestPublisher<String> =
    \.name <£> URLSession.shared.requester
        .validateStatusCode()
        .decode(using: userDecoder)
```

### Applicative — combining independent requests

`apply` (or `<*>`) runs two `RequestPublisher`s against the same `URLRequest` and zips their results:

```swift
struct Dashboard { let user: User; let stats: Stats }

// Lift the constructor into a publisher, then apply each field independently.
let dashboardPublisher: RequestPublisher<Dashboard> =
    RequestPublisher.pure(curry(Dashboard.init))
    <*> URLSession.shared.requester.validateStatusCode().decode(using: userDecoder)
    <*> URLSession.shared.requester.validateStatusCode().decode(using: statsDecoder)
```

### Monad — chaining dependent requests

`flatMap` (or `>>-`) threads the same base `URLRequest` through a dependent chain:

```swift
// Fetch a user, then fetch their team using the team ID from the first response.
let userAndTeam: RequestPublisher<(User, Team)> =
    URLSession.shared.requester
        .validateStatusCode()
        .decode(using: userDecoder)
        >>- { user in
            // swiftlint:disable:next force_unwrapping
            let teamURL = URL(string: "https://api.example.com/teams/\(user.teamId)")!
            return URLSession.shared.requester
                .validateStatusCode()
                .decode(using: teamDecoder)
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
        .decode(using: userDecoder)
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

### `NetworkTask` — async/await variant

`NetworkTask<A>` is the async/await counterpart to `RequestPublisher<A>`. It is a `ZIO<URLRequest, A, HTTPError>` — a `FunctionWrapper` around `(URLRequest) -> DeferredTask<Result<A, HTTPError>>`. No Combine required.

```swift
// NetworkTask<A> = ZIO<URLRequest, A, HTTPError>
//   = (URLRequest) -> DeferredTask<Result<A, HTTPError>>
public typealias NetworkTask<A: Sendable> = ZIO<URLRequest, A, HTTPError>

// Raw HTTP response pair — counterpart to Requester
public typealias TaskRequester = NetworkTask<(Data, HTTPURLResponse)>
```

`URLSession` gains a `.taskRequester` property parallel to `.requester`:

```swift
let taskRequester: TaskRequester = URLSession.shared.taskRequester
```

The same pipeline steps are available via `validateStatusCode()` and `decode(using:)`:

```swift
struct User: Decodable, Sendable { let id: Int; let name: String }

let getUser: NetworkTask<User> =
    URLSession.shared.taskRequester
        .validateStatusCode()
        .decode(using: JSONDecoder())

let request = URLRequest(url: URL(string: "https://api.example.com/users/1")!)
let result: Result<User, HTTPError> = await getUser(request).run()
```

Because `NetworkTask` is a `ZIO` (`FunctionWrapper`), it participates in the same Functor / Monad / Applicative hierarchy as `RequestPublisher` through the FP operators.

---

## NetworkServer

An embedded HTTP server backed by SwiftNIO. Routes are built by Kleisli-composing (`>=>`) a series of lifting functions, then wrapping the result with `when(…)`. Routers are values — they combine with `<|>`, adapt their environment with `contramap`, and are injected into the server via `Reader`.

### Mental model

```
get(path, params:, query:)    — GET route entry point
post / put / patch / delete   — other HTTP verbs; same signature

>=> ignoreBody()              — no body; imposes no Decodable constraint
 or decodeBody()              — decode body as B using env's DataDecoderFactory (Env: HasDataDecoderFactory)

>=> .response { req in … }   — lift closure into Effect<TypedRequest, Env, Response, ResponseError>

when(chain)                   — wrap into Router<DefaultEnv>
when(chain, injecting: T.self) — wrap into Router<T> for custom environments
```

Multiple routers combine with `<|>`. The operator tries the left router first and falls through to the right only on a 404 (unmatched route). Query-param errors (400) and body-decode errors (400) stop immediately without trying the next router.

The environment is injected **once at startup** via `runReader`. Every `>=>` step and every `.response` closure is pure — no side effects, no env access — until `startServer(…).runReader(env)` is called.

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
    get("/ping") >=> ignoreBody() >=> .response { _ in .html("pong") }
)

Thread.detachNewThread {
    _ = startServer(port: 8080, router: router).runReader(DefaultEnv())
}
```

### Typed URL parameters

Declare a `Decodable` struct whose property names match the `:placeholder` names in the route pattern. `URLParamsDecoder` maps path segments to struct fields using their string values.

```swift
struct AlbumID: Decodable { let id: String }

let router = when(
    get("/albums/:id", params: AlbumID.self)
    >=> ignoreBody()
    >=> .response { req in .html("Album: \(req.urlParams.id)") }
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
    >=> .response { req in .html("Album \(req.urlParams.albumId), photo \(req.urlParams.photoId)") }
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
         >=> .response { req in .html("Numeric album: \(req.urlParams.id)") })
    <|> when(get("/albums/:id", params: StringSlug.self) >=> ignoreBody()
             >=> .response { req in .html("Album slug: \(req.urlParams.id)") })
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
    >=> .response { req in
        let page  = req.queryParams.page  ?? 1
        let limit = req.queryParams.limit ?? 10
        return .plainText("page=\(page) limit=\(limit)")
    }
)
```

### Returning JSON

Use `.json(_:encoder:)` — pass the value and any `DataEncoderFactory` (e.g. a `JSONEncoder`). The factory is typically injected from a `Reader` environment or captured from an outer scope:

```swift
struct Album: Codable {
    let id:    Int
    let title: String
}

let router = when(
    get("/albums/1")
    >=> ignoreBody()
    >=> .response { _ in .json(Album(id: 1, title: "Kind of Blue"), encoder: JSONEncoder()) }
)
```

Pre-configure a `JSONEncoder` and reuse it across handlers:

```swift
let prettyEncoder: JSONEncoder = {
    let e = JSONEncoder()
    e.outputFormatting    = [.prettyPrinted, .sortedKeys]
    e.keyEncodingStrategy = .convertToSnakeCase
    return e
}()

// Use directly in any handler:
.json(myValue, encoder: prettyEncoder)
.json(myValue, encoder: prettyEncoder, status: .created)
```

### Body decoding

Use `decodeBody(using:)` as the middle step in the Kleisli chain. The lens extracts the decoder from the environment, making the dependency explicit at the call site and letting different endpoints use different decoding strategies. A decode failure returns 400 before the handler is called.

```swift
struct CreateAlbum: Decodable { let title: String }
struct Album:       Codable   { let id: Int; let title: String }

struct AppEnv: HasDictionaryDecoderFactory, Sendable {
    let decoder: JSONDecoder
    var dictionaryDecoderFactory: DictionaryDecoderFactory { DefaultEnv().dictionaryDecoderFactory }
}

let router = when(
    post("/albums")
    >=> decodeBody(using: \.decoder)
    >=> .response { (req: TypedRequest<Empty, Empty, CreateAlbum>) in
        .json(Album(id: nextID(), title: req.body.title), encoder: JSONEncoder(), status: .created)
    },
    injecting: AppEnv.self
)
```

The lens can also target a pre-built `DataDecoder<B>` stored on the environment (avoids re-building the decoder per request), or a `DataDecoderFactory` property for when the type must be inferred:

```swift
// DataDecoder<B> stored directly — zero allocation per request
>=> decodeBody(using: \.albumDecoder)   // where albumDecoder: DataDecoder<CreateAlbum>

// DataDecoderFactory stored on env — type B inferred from context
>=> decodeBody(using: \.jsonDecoder)    // where jsonDecoder: JSONDecoder (or any DataDecoderFactory)
```

Combine URL params, query params, and a body in one route:

```swift
struct AlbumID:     Decodable { let id: Int }
struct Format:      Decodable { let format: String? }
struct CreatePhoto: Decodable { let caption: String; let data: String }

let router = when(
    post("/albums/:id/photos", params: AlbumID.self, query: Format.self)
    >=> decodeBody(using: \.decoder)
    >=> .response { (req: TypedRequest<AlbumID, Format, CreatePhoto>) in
        .html("Uploaded to album \(req.urlParams.id) as \(req.queryParams.format ?? "jpeg")")
    },
    injecting: AppEnv.self
)
```

### Combining routers

`<|>` is the ordered-choice operator for routers. It tries the left side first; it falls through to the right only when the left returns 404.

```swift
struct Env: HasDictionaryDecoderFactory, Sendable {
    let decoder: JSONDecoder
    var dictionaryDecoderFactory: DictionaryDecoderFactory { DefaultEnv().dictionaryDecoderFactory }
}

let router: Router<Env> =
    when(get("/ping")   >=> ignoreBody() >=> .response { _ in .html("pong") }, injecting: Env.self)
    <|> when(get("/health") >=> ignoreBody() >=> .response { _ in .html("ok") }, injecting: Env.self)
    <|> when(
        post("/echo")
        >=> decodeBody(using: \.decoder)
        >=> .response { (req: TypedRequest<Empty, Empty, [String: String]>) in
            .json(req.body, encoder: JSONEncoder())
        },
        injecting: Env.self
    )
```

`Router.empty` is the identity — a router that always returns 404:

```swift
let empty = Router<DefaultEnv>.empty
// empty.handle.runReader(DefaultEnv())(request) always yields .failure(.notFound)
```

### `.response` — lifting closure variants

`.response` is a static factory on `Effect` that lifts any of several closure shapes into an `Effect<TypedRequest<U,Q,B>, Env, Response, ResponseError>`, which composes directly with the preceding `>=>` chain. Swift infers the `Effect` type from context, so the `Effect.` prefix is not needed:

```swift
// Sync failable — returns Result<Response, ResponseError>
.response { req -> Result<Response, ResponseError> in
    guard req.urlParams.id > 0 else { return .badRequest("id must be positive") }
    return .json(myAlbum, encoder: JSONEncoder())
}

// Async failable — returns DeferredTask<Result<Response, ResponseError>>
.response { req in
    DeferredTask {
        guard let album = await db.fetchAlbum(req.urlParams.id) else { return .notFound }
        return .json(album, encoder: JSONEncoder())
    }
}

// Combine env-independent — encoder inline; mapError lifts EncodingError into ResponseError
.response { req in
    fetchAlbumPublisher(req.urlParams.id)      // AnyPublisher<Album, ResponseError>
        .encode(using: JSONEncoder(), mapError: { ResponseError.serverError($0.localizedDescription) })
        .map { Response(status: .ok, headers: [("Content-Type", "application/json")], body: $0) }
        .eraseToAnyPublisher()
}

// Combine env-dependent — encoder comes from the environment
.response { req, env in
    fetchAlbumPublisher(req.urlParams.id)      // AnyPublisher<Album, ResponseError>
        .encode(using: env.encoder, mapError: { ResponseError.serverError($0.localizedDescription) })
        .map { Response(status: .ok, headers: [("Content-Type", "application/json")], body: $0) }
        .eraseToAnyPublisher()
}
```

### Environment-dependent handlers

When the handler needs values from the server's environment (database connections, config, auth tokens), return a `Reader` from the closure. Custom environments must conform to `HasDictionaryDecoderFactory` for route parameter decoding — delegate to `DefaultEnv` for the default implementation:

```swift
struct AppEnv: HasDictionaryDecoderFactory, Sendable {
    let db:     Database
    let config: Config
    var dictionaryDecoderFactory: DictionaryDecoderFactory { DefaultEnv().dictionaryDecoderFactory }
}

struct AlbumID: Decodable { let id: Int }

let router: Router<AppEnv> = when(
    get("/albums/:id", params: AlbumID.self)
    >=> ignoreBody()
    >=> .response { req, env in
        DeferredTask {
            guard let album = await env.db.fetchAlbum(id: req.urlParams.id) else {
                return .notFound
            }
            return .json(album, encoder: env.encoder)
        }
    },
    injecting: AppEnv.self
)

// Inject the environment at startup, not at route definition time.
startServer(port: 8080, router: router).runReader(AppEnv(db: db, config: config))
```

For synchronous env access:

```swift
struct ConfigEnv: HasDictionaryDecoderFactory, Sendable {
    let greeting: String
    var dictionaryDecoderFactory: DictionaryDecoderFactory { DefaultEnv().dictionaryDecoderFactory }
}

let router: Router<ConfigEnv> = when(
    get("/hello")
    >=> ignoreBody()
    >=> .response { _, env in .html(env.greeting) },
    injecting: ConfigEnv.self
)

startServer(port: 8080, router: router).runReader(ConfigEnv(greeting: "Hi there!"))
```

### `contramap` — composing routers with different environments

`contramap` adapts a `Router<SmallEnv>` to work inside a larger environment by providing a function `(World) -> SmallEnv`. This lets you build modular routers that know only about their own slice of the environment, then assemble them at the top level:

```swift
// Each sub-env must conform to HasDictionaryDecoderFactory.
struct AppEnv: HasDictionaryDecoderFactory, Sendable {
    let auth: AuthEnv
    let data: DataEnv
    var dictionaryDecoderFactory: DictionaryDecoderFactory { DefaultEnv().dictionaryDecoderFactory }
}

// Each sub-module declares only what it needs (also conforming to HasDictionaryDecoderFactory).
let authRouter: Router<AuthEnv> = /* login/logout routes */
let dataRouter: Router<DataEnv> = /* resource routes */

// Combine at the app level, mapping each router to its env slice.
let appRouter: Router<AppEnv> =
    authRouter.contramap(\.auth)
    <|> dataRouter.contramap(\.data)

startServer(port: 8080, router: appRouter).runReader(AppEnv(auth: authEnv, data: dataEnv))
```

### `Result<Response, ResponseError>` factories

Handlers return `Result<Response, ResponseError>`. Static factories let you construct these with leading-dot syntax:

```swift
// Success
.json(album, encoder: JSONEncoder())                      // 200 application/json
.json(album, encoder: JSONEncoder(), status: .created)    // 201
.html("<h1>Hello</h1>")                                   // 200 text/html
.html("<b>bad</b>", status: .badRequest)
.plainText("OK")
.raw(pdfData)                                             // application/octet-stream
.image(jpegData)                                          // image/jpeg
.image(pngData, mimeType: "image/png")

// Failure
.notFound                                                 // 404
.badRequest("missing 'title'")                            // 400
.serverError("db unavailable")                            // 500
```

### `ResponseError` reference

```swift
ResponseError.notFound                          // 404 text/plain "Not Found"
ResponseError.badRequest("missing 'title'")     // 400 text/plain
ResponseError.serverError("db unavailable")     // 500 text/plain

// Custom status/headers/body
ResponseError(status: .unauthorized, headers: [("WWW-Authenticate", "Bearer")], body: Data())

// Encoded body — factory mirrors the Result factories but returns ResponseError directly
ResponseError.json(Payload(code: 42), encoder: JSONEncoder(), status: .unprocessableEntity)
ResponseError.html("<b>error</b>", status: .badRequest)
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

struct AppEnv: HasDictionaryDecoderFactory, Sendable {
    var albums: [Album]
    let decoder: JSONDecoder
    let encoder: DataEncoderFactory
    var dictionaryDecoderFactory: DictionaryDecoderFactory { DefaultEnv().dictionaryDecoderFactory }

    static let live = AppEnv(
        albums: [
            Album(id: 1, title: "Kind of Blue",    year: 1959),
            Album(id: 2, title: "A Love Supreme",  year: 1964),
            Album(id: 3, title: "In a Silent Way", year: 1969),
        ],
        decoder: JSONDecoder(),
        encoder: JSONEncoder()
    )
}

// MARK: - Route params

struct AlbumID:   Decodable { let id:   Int }
struct YearQuery: Decodable { let year: Int? }

// MARK: - Router

let router: Router<AppEnv> =

    // GET /albums — list all, optionally filtered by ?year=
    when(
        get("/albums", query: YearQuery.self)
        >=> ignoreBody()
        >=> .response { req, env in
            let albums = req.queryParams.year.map { y in env.albums.filter { $0.year == y } }
                         ?? env.albums
            return .json(albums, encoder: env.encoder)
        },
        injecting: AppEnv.self
    )

    // GET /albums/:id — fetch one album by integer ID
    <|> when(
        get("/albums/:id", params: AlbumID.self)
        >=> ignoreBody()
        >=> .response { req, env in
            guard let album = env.albums.first(where: { $0.id == req.urlParams.id }) else {
                return .notFound
            }
            return .json(album, encoder: env.encoder)
        },
        injecting: AppEnv.self
    )

    // POST /albums — create a new album from a JSON body
    <|> when(
        post("/albums")
        >=> decodeBody(using: \.decoder)
        >=> .response { (req: TypedRequest<Empty, Empty, CreateAlbum>, env: AppEnv) in
            let newAlbum = Album(id: env.albums.count + 1, title: req.body.title, year: req.body.year)
            return .json(newAlbum, encoder: env.encoder, status: .created)
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
struct WebEnv: HasDictionaryDecoderFactory, Sendable {
    let templates: HTMLEnvironment
    let db: Database
    var dictionaryDecoderFactory: DictionaryDecoderFactory { DefaultEnv().dictionaryDecoderFactory }
}

let router: Router<WebEnv> = when(
    get("/")
    >=> ignoreBody()
    >=> .response { _, env in
        let ctx: Context = [
            "title":  .string("Albums"),
            "albums": .list(env.db.allAlbums().map { ["title": .string($0.title)] }),
        ]
        switch render("{{#include page}}", ctx).runReader(env.templates) {
        case .success(let html): return .html(html)
        case .failure(let err):  return .serverError(String(describing: err))
        }
    },
    injecting: WebEnv.self
)

startServer(port: 8080, router: router).runReader(
    WebEnv(templates: .live(path: "/app/templates"), db: myDB)
)
```

---

## Multipeer

A wrapper around `MultipeerConnectivity` exposing **both a Combine API and a `DeferredTask`/`DeferredStream` API side by side**, implemented independently so the deferred-concurrency path stays Combine-free (and portable as a shape to non-Apple transports — see [Cross-platform notes](#cross-platform-notes-multipeer)).

> **Platform availability:** the whole target is gated on `#if canImport(MultipeerConnectivity)`. On watchOS and Linux the target compiles to an empty module — using any of these symbols requires iOS / macOS / tvOS / visionOS.

### Architecture

Every event source has two parallel surfaces — advertising, browsing, and session traffic each ship a `Publisher` form and a `DeferredStream` form, fed by independent delegate plumbing. The session's one-shot operations (`invite`, `send`, `sendToAll`) ship in both flavours too.

| Concept                | Combine                                         | Deferred concurrency                                  |
| ---------------------- | ----------------------------------------------- | ----------------------------------------------------- |
| Advertising            | `MultipeerAdvertiserPublisher`                  | `multipeerAdvertiserStream(...)`                      |
| Browsing               | `MultipeerBrowserPublisher`                     | `multipeerBrowserStream(...)`                         |
| Connection events      | `MultipeerSession.connections`                  | `MultipeerSession.connectionsStream`                  |
| Incoming traffic       | `MultipeerSession.messages`                     | `MultipeerSession.messagesStream`                     |
| Invite a peer          | `session.invite(peer:browser:context:timeout:)` | `session.inviteTask(peer:browser:context:timeout:)`   |
| Send to one peer       | `session.send(_:to:reliable:)`                  | `session.sendTask(_:to:reliable:)`                    |
| Send to all peers      | `session.sendToAll(_:reliable:)`                | `session.sendToAllTask(_:reliable:)`                  |

The Combine side uses `PassthroughSubject`s; the deferred side uses an `AsyncMulticaster<Element>` (a lock-protected fan-out of `AsyncStream` continuations). Delegate methods feed both, so subscribing to one surface never costs anything on the other.

### Setting up a session

```swift
import Combine
import Multipeer
import MultipeerConnectivity

let me = MCPeerID(displayName: "device-A")
let session = MultipeerSession(myselfAsPeer: me)
```

### Advertising

#### Combine

`MultipeerAdvertiserPublisher` creates a fresh `MCNearbyServiceAdvertiser` per subscription and stops it on cancel.

```swift
let advertising = MultipeerAdvertiserPublisher(
    myselfAsPeer: me,
    serviceType: "ms-chat",
    discoveryInfo: ["role": "host"]
)
.sink(
    receiveCompletion: { print("advertiser stopped: \($0)") },
    receiveValue: { event in
        if case let .didReceiveInvitationFromPeer(_, _, accept) = event {
            accept(true, session.session)   // accept every invitation
        }
    }
)
// advertising.cancel() stops advertising
```

#### DeferredStream

`multipeerAdvertiserStream(...)` returns a `DeferredStream<Result<MultipeerAdvertiserEvent, Error>>`. A fresh advertiser is created on each `for await` iteration; advertising stops when the iterator terminates.

```swift
let stream = multipeerAdvertiserStream(myselfAsPeer: me, serviceType: "ms-chat")

let task = Task {
    for await event in stream {
        switch event {
        case .success(.didReceiveInvitationFromPeer(_, _, let accept)):
            accept(true, session.session)
        case .failure(let error):
            print("advertiser failed: \(error)")
        }
    }
}
// task.cancel() stops advertising
```

### Browsing

#### Combine

```swift
let browsing = MultipeerBrowserPublisher(myselfAsPeer: me, serviceType: "ms-chat")
    .sink(
        receiveCompletion: { _ in },
        receiveValue: { event in
            switch event {
            case let .foundPeer(remote, info, browser):
                print("found \(remote.displayName) info=\(info ?? [:])")
                browser.invitePeer(remote, to: session.session, withContext: nil, timeout: 10)
            case let .lostPeer(remote):
                print("lost \(remote.displayName)")
            }
        }
    )
```

#### DeferredStream

```swift
Task {
    for await event in multipeerBrowserStream(myselfAsPeer: me, serviceType: "ms-chat") {
        switch event {
        case .success(.foundPeer(let remote, _, let browser)):
            browser.invitePeer(remote, to: session.session, withContext: nil, timeout: 10)
        case .success(.lostPeer(let remote)):
            print("lost \(remote.displayName)")
        case .failure(let error):
            print("browser failed: \(error)")
        }
    }
}
```

### Session lifecycle (connections + traffic)

#### Combine

```swift
let connectionsToken = session.connections.sink { event in
    switch event {
    case .peerIsConnecting(let p, _): print("connecting: \(p.displayName)")
    case .peerConnected(let p, _):    print("connected: \(p.displayName)")
    case .peerDisconnected(let p, _): print("disconnected: \(p.displayName)")
    }
}

let messagesToken = session.messages.sink { msg in
    if case .data(let payload, let from, _) = msg {
        print("\(from.displayName) sent \(payload.count) bytes")
    }
}
```

#### DeferredStream

```swift
Task {
    for await event in session.connectionsStream {
        switch event {
        case .peerIsConnecting(let p, _): print("connecting: \(p.displayName)")
        case .peerConnected(let p, _):    print("connected: \(p.displayName)")
        case .peerDisconnected(let p, _): print("disconnected: \(p.displayName)")
        }
    }
}

Task {
    for await msg in session.messagesStream {
        if case .data(let payload, let from, _) = msg {
            print("\(from.displayName) sent \(payload.count) bytes")
        }
    }
}
```

Both `messagesStream` and `connectionsStream` are multicast — every `for await` registers a fresh continuation, so multiple consumers can read the same session independently.

### Inviting a peer

#### Combine

`invite` returns a `Publisher` that emits the peer each time it becomes connected (the invitation is sent on subscription).

```swift
let inviteToken = session
    .invite(peer: remote, browser: browser, context: nil, timeout: 10)
    .first()
    .sink { joined in print("\(joined.displayName) joined the session") }
```

#### DeferredTask

`inviteTask` returns a `DeferredTask<MCPeerID?>` that suspends until the peer first becomes connected, returning `nil` if the session ends first. The continuation is registered **before** the invite is sent, so the connect event can never race past it.

```swift
let joined = await session
    .inviteTask(peer: remote, browser: browser, context: nil, timeout: 10)
    .run()

if let joined {
    print("\(joined.displayName) joined the session")
}
```

### Sending data

The synchronous Combine flavour returns `Result<Void, Error>` immediately; the deferred flavour wraps the same call in a `DeferredTask` for composition with the rest of the FP toolkit.

```swift
// Sync (Combine-friendly):
let result = session.send(Data("ping".utf8), to: remote, reliable: true)
let broadcast = session.sendToAll(Data("hello all".utf8))

// DeferredTask:
let resultTask     = session.sendTask(Data("ping".utf8), to: remote, reliable: true)
let broadcastTask  = session.sendToAllTask(Data("hello all".utf8))

let result    = await resultTask.run()
let broadcast = await broadcastTask.run()
```

### FP composition

Because `sendTask` returns a `DeferredTask<Result<Void, Error>>`, it slots into the FP toolkit (`flatMap`, `>=>`, `ZIO`, etc.). Example: chain three sends as one referentially-transparent task and run it lazily.

```swift
import FP

let send: (String, MCPeerID) -> DeferredTask<Result<Void, Error>> = { text, peer in
    session.sendTask(Data(text.utf8), to: peer)
}

let handshake = send("hello", remote)
    .flatMap { _ in send("world", remote) }
    .flatMap { _ in send("done",  remote) }

_ = await handshake.run()
```

### Mixing both surfaces

The Combine and deferred-concurrency surfaces share a single underlying `MCSession` — pick the one that fits each callsite without paying for the other. A SwiftUI binding can subscribe through `messages`, while a long-running domain task reads `messagesStream`.

```swift
final class ChatViewModel: ObservableObject {
    @Published var transcript: [String] = []
    private var cancellables = Set<AnyCancellable>()

    init(session: MultipeerSession) {
        // UI path: Combine -> @Published
        session.messages
            .compactMap { msg -> String? in
                guard case .data(let data, let from, _) = msg else { return nil }
                return "\(from.displayName): \(String(data: data, encoding: .utf8) ?? "?")"
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] line in self?.transcript.append(line) }
            .store(in: &cancellables)

        // Persistence path: DeferredStream -> background task
        Task.detached {
            for await msg in session.messagesStream {
                if case .data(let data, let from, _) = msg {
                    await ChatStore.shared.append(data, from: from)
                }
            }
        }
    }
}
```

### Cross-platform notes (Multipeer)

`MultipeerConnectivity` is an Apple framework — it has no Linux port and isn't expected to get one. Every Multipeer source file is wrapped in `#if canImport(MultipeerConnectivity)`, so the package itself **still builds on Linux** with the Multipeer target compiled to an empty module; you just can't construct any of its symbols there.

The deferred-concurrency surface (`DeferredStream`, `DeferredTask`, `AsyncMulticaster`) is intentionally Combine-free. To run the **same shape** of API on Linux, the path is:

1. Define a transport-agnostic protocol that abstracts the three pieces — advertise, browse, session — leaving the existing MC types as the Apple implementation.
2. Provide a Linux implementation (e.g. Bonjour / DNS-SD via `swift-nio` or `libavahi`, or a UDP-multicast + TCP layer of your own).
3. The `DeferredStream` / `DeferredTask` plumbing carries over unchanged — it depends only on `Foundation` and `AsyncStream`, both available on Linux.

Until that protocol exists, treat the Multipeer target as Apple-only and rely on the `canImport` guard to keep cross-platform consumers compiling.

---

## WebSocketClient

Full-duplex WebSocket client with **two parallel APIs**: a Combine `WebSocket` class and a
lazy `WebSocketConnection` value for `DeferredTask` / `DeferredStream` composition.

### Combine API

```swift
import Combine
import WebSocketClient

var cancellables = Set<AnyCancellable>()

let socket = URLSession.shared.webSocket(with: URL(string: "wss://echo.example.com")!)

// Receive — task starts on first subscriber demand
socket.publisher
    .sink(
        receiveCompletion: { print("closed:", $0) },
        receiveValue: { message in
            if case .string(let text) = message { print("←", text) }
        }
    )
    .store(in: &cancellables)

// Send — lazy: write fires only when subscribed
socket.send("hello")
    .sink(receiveCompletion: { _ in }, receiveValue: { print("sent") })
    .store(in: &cancellables)

// Periodic health-check
socket.startPinging(every: 30)
    .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
    .store(in: &cancellables)
```

Custom headers (auth):

```swift
var req = URLRequest(url: URL(string: "wss://api.example.com/ws")!)
req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
let socket = URLSession.shared.webSocket(with: req)
```

Echo round-trip:

```swift
socket.publisher
    .compactMap { if case .string(let t) = $0 { return t } else { return nil } }
    .flatMap(maxPublishers: .max(1)) { socket.send("echo: \($0)") }
    .sink(receiveCompletion: { _ in }, receiveValue: { })
    .store(in: &cancellables)
```

### Async API (DeferredTask / DeferredStream)

`webSocketConnection(with:)` returns `DeferredTask<WebSocketConnection>` — nothing touches
the network until `.run()` is called, making connections safe to pass as pure values.

```swift
import FP
import WebSocketClient

let connectionTask = URLSession.shared.webSocketConnection(
    with: URL(string: "wss://echo.example.com")!
)

// Open the connection (TCP + WebSocket upgrade happen here)
let conn = await connectionTask.run()

// Send immediately after opening
_ = await conn.send(.string("hello")).run()

// Stream incoming messages
for await result in conn.receive {
    switch result {
    case .success(.string(let text)): print("←", text)
    case .success(.data(let bytes)):  print("← \(bytes.count) bytes")
    case .failure(let err):           print("error:", err); break
    default: break
    }
}

// Close cleanly
await conn.close.run()
```

Inside a SwiftRex `Behavior`:

```swift
import SwiftRex
import WebSocketClient

let chatBehavior = Behavior<AppAction, AppState, AppEnvironment> { action, _ in
    guard case .connectChat(let url) = action else { return .doNothing }

    return .produce { ctx in
        Effect.task {
            let conn = await ctx.environment.openWebSocket(url).run()
            // Long-running receive loop
            for await result in conn.receive {
                if case .success(.string(let msg)) = result {
                    return .chatMessageReceived(msg)
                }
            }
            return .chatDisconnected
        }
    }
}
```

### Testability

`URLSessionWebSocketTaskProtocol` lets you inject a mock:

```swift
final class MockWebSocketTask: URLSessionWebSocketTaskProtocol {
    var sentMessages: [URLSessionWebSocketTask.Message] = []
    var nextResult: Result<URLSessionWebSocketTask.Message, Error>?

    func resume() {}
    func cancel(with code: URLSessionWebSocketTask.CloseCode, reason: Data?) {}
    func sendPing(pongReceiveHandler: @escaping @Sendable (Error?) -> Void) { pongReceiveHandler(nil) }

    func send(_ message: URLSessionWebSocketTask.Message,
              completionHandler: @escaping @Sendable (Error?) -> Void) {
        sentMessages.append(message); completionHandler(nil)
    }

    func receive(completionHandler: @escaping @Sendable (Result<URLSessionWebSocketTask.Message, Error>) -> Void) {
        nextResult.map(completionHandler)
    }
}
```

---

## BonjourService

Bonjour service **discovery** and **advertising** with both Combine publishers and
`DeferredStream` async APIs. All four combinations are provided:

| Direction | Combine | Async |
|-----------|---------|-------|
| Browse    | `NWBrowserPublisher` | `bonjourBrowserStream(...)` |
| Advertise | `NWListenerPublisher` | `bonjourListenerStream(...)` |

### Browse — Combine

```swift
import Combine
import BonjourService

var cancellables = Set<AnyCancellable>()

NWBrowserPublisher(serviceType: "_myapp._tcp.", domain: nil)
    .sink(
        receiveCompletion: { completion in
            switch completion {
            case .finished: print("stopped")
            case .failure(.bonjourPermissionDenied): print("need local-network permission")
            case .failure(.didNotSearch(let err)):   print("error:", err)
            }
        },
        receiveValue: { event in
            switch event {
            case .didFind(let endpoint, let txt):
                print("found:", endpoint, "txt:", txt ?? [:])
            case .didRemove(let endpoint, _):
                print("gone:", endpoint)
            case .didUpdate(_, let new, let txt, _):
                print("updated to:", new, "txt:", txt ?? [:])
            }
        }
    )
    .store(in: &cancellables)
```

Track live service set:

```swift
NWBrowserPublisher(serviceType: "_http._tcp.", domain: nil)
    .scan([NWEndpoint]()) { set, event in
        switch event {
        case .didFind(let ep, _):             return set + [ep]
        case .didRemove(let ep, _):           return set.filter { $0 != ep }
        case .didUpdate(let old, let new, _, _): return set.map { $0 == old ? new : $0 }
        }
    }
    .sink { print("services:", $0) }
    .store(in: &cancellables)
```

### Browse — Async

```swift
import FP
import BonjourService

Task {
    for await result in bonjourBrowserStream(serviceType: "_myapp._tcp.") {
        switch result {
        case .success(.didFind(let endpoint, let txt)):
            print("found:", endpoint, "txt:", txt ?? [:])
        case .success(.didRemove(let endpoint, _)):
            print("gone:", endpoint)
        case .failure(let err):
            print("error:", err)
        default: break
        }
    }
}
```

### Advertise — Combine

```swift
// throws if the port is already in use
let publisher = try NWListenerPublisher(
    serviceType: "_myapp._tcp.",
    serviceName: "My Device",
    port: .any           // OS assigns; check the .ready event for the actual port
)

publisher
    .sink(
        receiveCompletion: { print("stopped:", $0) },
        receiveValue: { event in
            switch event {
            case .ready(let port):
                print("advertising on port", port ?? 0)
            case .newConnection(let connection):
                connection.start(queue: .main)
                // set up receive / send on `connection`
            case .serviceRegistrationChanged(let change):
                print("registration:", change)
            }
        }
    )
    .store(in: &cancellables)
```

With TXT record metadata:

```swift
var txt = NWTXTRecord()
txt["version"] = "1.0"
txt["platform"] = "iOS"

let publisher = try NWListenerPublisher(
    serviceType: "_myapp._tcp.",
    serviceName: "My iPhone",
    txtRecord: txt
)
```

### Advertise — Async

```swift
Task {
    for await result in bonjourListenerStream(serviceType: "_myapp._tcp.", serviceName: "My Device") {
        switch result {
        case .success(.ready(let port)):
            print("advertising on port", port ?? 0)
        case .success(.newConnection(let connection)):
            connection.start(queue: .main)
            handleIncomingConnection(connection)
        case .failure(let err):
            print("error:", err)
        default: break
        }
    }
}
```

Inside a SwiftRex `Behavior`:

```swift
let advertiserBehavior = Behavior<AppAction, AppState, AppEnvironment> { action, _ in
    guard case .startAdvertising(let name) = action else { return .doNothing }
    return .produce { _ in
        Effect.stream {
            bonjourListenerStream(serviceType: "_myapp._tcp.", serviceName: name)
                .compactMap { result -> AppAction? in
                    switch result {
                    case .success(.ready(let port)):     return .advertisingStarted(port: port)
                    case .success(.newConnection(let c)): return .clientConnected(c)
                    case .failure(let err):              return .advertisingFailed(err)
                    default:                             return nil
                    }
                }
        }
    }
}
```

### Resolve endpoints

```swift
// Resolve a host/port to a concrete address
NWEndpoint.hostPort(host: "api.example.com", port: 443)
    .publisher()
    .sink(receiveCompletion: { _ in }, receiveValue: { resolved in
        print("host:", resolved.hostname ?? "?", "port:", resolved.port ?? 0)
    })
    .store(in: &cancellables)

// Resolve a Bonjour service endpoint
NWEndpoint.service(name: "My Server", type: "_http._tcp.", domain: "local.", interface: nil)
    .publisher()
    .sink(receiveCompletion: { _ in }, receiveValue: { resolved in
        if case .service(let ns, _, _) = resolved {
            print("IPs:", ns.parsedAddresses(), "port:", ns.port)
        }
    })
    .store(in: &cancellables)
```

### Legacy NetService API

```swift
// Browse with NetServiceBrowser
NetServiceBrowser()
    .publisher(serviceOfType: "_ssh._tcp.", inDomain: "local.")
    .sink(receiveCompletion: { _ in }, receiveValue: { event in
        if case .didFind(let service, _) = event.type {
            service.publisher(monitorDevice: .doNotMonitorTXTUpdates, timeout: 5)
                .compactMap { e -> [String]? in
                    guard case .didResolveAddress = e.type else { return nil }
                    return e.netService.parsedAddresses()
                }
                .first()
                .sink { print("SSH IPs:", $0) }
                .store(in: &cancellables)
        }
    })
    .store(in: &cancellables)

// Monitor TXT record changes
NetService(domain: "local.", type: "_airplay._tcp.", name: "Apple TV")
    .publisher(monitorDevice: .keepMonitoringTXTUpdates)
    .compactMap { e -> [String: Data]? in
        guard case let .didUpdateTXTRecord(txt) = e.type else { return nil }
        return txt
    }
    .sink { print("AirPlay TXT updated:", $0) }
    .store(in: &cancellables)
```

### IP address helper

```swift
let addr = IP("192.168.1.100")   // .ipv4
let v6   = IP("::1")             // .ipv6

print(addr?.ipString)    // "192.168.1.100"
print(v6?.ipUrlString)   // "[::1]"   ← brackets for URL use

// Prefer IPv6 over IPv4 in a list
let preferred = [IP("192.168.1.1")!, IP("::1")!].preferredAddress // → .ipv6(::1)
```

---

## Design principles

All three packages follow the same functional conventions via [`FP`](https://github.com/luizmb/FP):

- **`Reader`** for dependency injection (template environment, server environment, request threading). No `init` injection, no stored globals.
- **`Result`** instead of `throws` at all public API boundaries. Errors are values.
- **`DeferredTask`** for async work in the server (lazy, nothing runs until `.run()` is called). **`Publisher`** (Combine) for the HTTP client (composable, cancellable, backpressure-aware).
- **`FunctionWrapper`** for any `(A) -> B` that should be composable — `RequestPublisher`, `DataDecoder`, `DataEncoder` all conform.
- **Alternative (`<|>`)** for router composition — tries left then right (only 404 falls through), identity is `Router.empty`.
- **No crashing operations** — no force-unwrap, no `fatalError`, no `try!`. All failure paths return `Result` or publisher errors.
