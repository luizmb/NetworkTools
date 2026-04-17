# NetworkTools

A suite of three Swift packages for HTML templating, HTTP networking, and HTTP server hosting. Built on functional programming principles using [`FP`](https://github.com/luizmb/FP): every public API uses `Reader` for dependency injection, `Result` for error handling, `Publisher` (Combine) for async work, and `FunctionWrapper` for composable function types. No force-unwraps, no `fatalError`, no silent failures.

**Platforms:** macOS 13+, iOS 16+, tvOS 16+, watchOS 9+

---

## Packages

- [HTMLTemplating](#htmltemplating) — file-based HTML template engine with `{{}}` directives
- [NetworkClient](#networkclient) — composable HTTP client built on `URLSession` and Combine
- [NetworkServer](#networkserver) — embedded NIO-backed HTTP server with a functional routing DSL

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
    // Base directory where fragment files live.
    public let fragmentsDir: String
    // Injectable IO: given a full file path, returns its contents or an error.
    public let readFile: (String) -> Result<String, Error>

    // Full init — supply your own readFile for testing or non-filesystem sources.
    public init(fragmentsDir: String, readFile: @escaping (String) -> Result<String, Error>)

    // Convenience: uses String(contentsOfFile:encoding:) as the readFile implementation.
    public init(fragmentsDir: String)
}
```

The engine constructs `"\(fragmentsDir)/\(name).html.template"` and passes it to `readFile`. Injecting `readFile` makes the IO mockable without touching the path logic.

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
let env = HTMLEnvironment(fragmentsDir: "/path/to/fragments")

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

### Bundle-based loader

For templates bundled inside an app target:

```swift
// Looks for Resources/templates/<name>.html in the given bundle.
let result: Result<String, TemplateError> = loadTemplate("index", in: .main)

switch result {
case .success(let source):
    let html = try render(source, ctx).runReader(env).get()
case .failure(.notFound(let name)):
    print("Template '\(name)' not found in bundle")
case .failure(.readError(let name, let error)):
    print("Failed to read '\(name)': \(error)")
}
```

### Composing with Reader

Because `render` returns a `Reader`, you can swap the environment entirely without touching the template logic:

```swift
let pageReader: Reader<HTMLEnvironment, Result<String, TemplateError>> =
    render("{{#include layout}}", [
        "title":   .string("Dashboard"),
        "content": .string(bodyHTML),
    ])

// Production: load from disk using String(contentsOfFile:encoding:).
let prodHTML = pageReader.runReader(HTMLEnvironment(fragmentsDir: "/app/templates"))

// Testing: inject in-memory fragments — no filesystem, no temp files.
let stubs = ["layout": "<html>{{content}}</html>"]
let testEnv = HTMLEnvironment(fragmentsDir: "") { path in
    let name = URL(fileURLWithPath: path)
        .deletingPathExtension()   // drop .template
        .deletingPathExtension()   // drop .html
        .lastPathComponent
    return stubs[name].map(Result.success)
        ?? .failure(URLError(.fileDoesNotExist))
}
let testHTML = pageReader.runReader(testEnv)
```

The IO is fully contained in `readFile` — `render` never touches the filesystem directly. `fragmentsDir` is always available if the custom `readFile` implementation needs it for path construction.

---

## NetworkClient

A composable HTTP client. The core type `RequestPublisher<A>` is a `FunctionWrapper` around `(URLRequest) -> AnyPublisher<A, HTTPError>`, forming a Reader + Publisher monad stack. Every step in a request pipeline — sending, validating, decoding — is a composable value.

### Core types

```swift
// The primary type: a reusable function from URLRequest to a typed response publisher.
public struct RequestPublisher<A>: FunctionWrapper<URLRequest, AnyPublisher<A, HTTPError>>

// Alias for the raw response pair before status/decoding.
public typealias Requester = RequestPublisher<(Data, HTTPURLResponse)>

// A reusable decoding function: Data -> Result<D, DecodingError>.
public struct DecoderResult<D>: FunctionWrapper<Data, Result<D, DecodingError>>

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

let decoder = JSONDecoder().decoderResult(for: User.self)

let userPublisher: AnyPublisher<User, HTTPError> =
    URLSession.shared.requester
        .validateStatusCode()           // fail on non-2xx
        .decode(User.self, decoder: decoder.run)  // decode JSON body
        (URLRequest(url: url))          // run against the request

userPublisher.sink(
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

// Or post-process with map:
let nameDecoder: DecoderResult<String> = userDecoder.map(\.name)
```

`DecoderResult` supports the full Functor / Applicative / Monad hierarchy.

### Functor — transforming responses

`map` transforms the output of a successful `RequestPublisher`:

```swift
let namePublisher: RequestPublisher<String> =
    URLSession.shared.requester
        .validateStatusCode()
        .decode(User.self, decoder: userDecoder.run)
        .map(\.name)

// Using the <£> operator (fmap):
let namePublisher2 = \.name <£> URLSession.shared.requester
    .validateStatusCode()
    .decode(User.self, decoder: userDecoder.run)
```

### Applicative — combining independent requests

`apply` (or `<*>`) zips two `RequestPublisher`s against the same `URLRequest`:

```swift
// Two independent decoders zipped into a tuple:
let fDecoder = RequestPublisher<(User) -> (User, Profile)>.pure { u in { p in (u, p) } }
let userReq    = makeUserRequest.validateStatusCode().decode(User.self,    decoder: userDecoder.run)
let profileReq = makeUserRequest.validateStatusCode().decode(Profile.self, decoder: profileDecoder.run)

let combined: RequestPublisher<(User, Profile)> = fDecoder <*> userReq <*> profileReq
```

### Monad — chaining dependent requests

`flatMap` (or `>>-`) threads the same base `URLRequest` through a dependent chain:

```swift
// Fetch a user, then fetch their team using the team ID from the first response:
let pipeline: RequestPublisher<Team> =
    URLSession.shared.requester
        .validateStatusCode()
        .decode(User.self, decoder: userDecoder.run)
        >>- { user in
            var teamReq = URLRequest(url: URL(string: "https://api.example.com/teams/\(user.teamId)")!)
            return URLSession.shared.requester
                .validateStatusCode()
                .decode(Team.self, decoder: teamDecoder.run)
        }
```

### Kleisli composition — point-free pipelines

Kleisli composition (`>=>`) sequences functions of the form `(A) -> RequestPublisher<B>`:

```swift
let fetchUser:    (Int)  -> RequestPublisher<User>    = { id in ... }
let fetchTeam:    (User) -> RequestPublisher<Team>    = { user in ... }
let fetchProject: (Team) -> RequestPublisher<Project> = { team in ... }

// Compose into a single (Int) -> RequestPublisher<Project>:
let fetchProjectForUser = fetchUser >=> fetchTeam >=> fetchProject

fetchProjectForUser(42)(URLRequest(url: baseURL))
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

An embedded HTTP server backed by SwiftNIO. `startServer` returns a `Reader<Handler, Result<Void, Error>>` — the `Handler` dependency is injected when running the reader, not at construction time.

### Core types

```swift
// A FunctionWrapper around (Request) -> AnyPublisher<Response, Never>.
public struct Handler: FunctionWrapper<Request, AnyPublisher<Response, Never>>

// A route matcher: returns a publisher if it matches, nil otherwise.
public typealias RouteMatcher = (Request) -> AnyPublisher<Response, Never>?

public struct Request {
    public let method: HTTPMethod
    public let uri: String
    public let body: Data
    public var pathParams: [String: String]

    public var path: String                    // URI without query string
    public var queryParams: [String: String]   // percent-decoded query parameters
    public func decodeBody<T: Decodable>(as: T.Type) -> Result<T, DecodingError>
}
```

### Response constructors

```swift
Response.html("<h1>Hello</h1>")                    // 200 text/html
Response.html("<h1>Not here</h1>", status: .notFound)
Response.json(Encodable)                           // 200 application/json, sorted keys
Response.json(Encodable, status: .created)
Response.image(jpegData)                           // 200 image/jpeg
Response.image(pngData, mimeType: "image/png")
Response.notFound                                  // 404 text/plain "Not Found"
Response.badRequest("missing field")               // 400 text/plain
Response.serverError("oops")                       // 500 text/plain
```

### Starting a server

```swift
let handler = Handler { request in
    Just(Response.html("<h1>Hello from \(request.path)</h1>"))
        .eraseToAnyPublisher()
}

// startServer returns a Reader — run it with a Handler to start blocking.
let result: Result<Void, Error> = startServer(port: 8080).runReader(handler)

if case .failure(let error) = result {
    print("Server failed:", error)
}
```

The call blocks until the server shuts down (or fails to bind).

### Routing with `route` and `firstMatch`

```swift
struct Album: Codable {
    let id: Int
    let title: String
}

let routes: [RouteMatcher] = [

    // Sync handler — return a Response directly.
    route(.GET, "/") { _ in
        Response.html("<h1>Welcome</h1>")
    },

    // Async handler — return AnyPublisher<Response, Never>.
    route(.GET, "/albums/:id") { request in
        let id = request.pathParams["id"] ?? ""
        return fetchAlbum(id: id)                     // AnyPublisher<Album, Never>
            .map { Response.json($0) }
            .eraseToAnyPublisher()
    },

    // POST with JSON body decoding.
    route(.POST, "/albums") { request in
        switch request.decodeBody(as: Album.self) {
        case .success(let album):
            return Just(Response.json(album, status: .created)).eraseToAnyPublisher()
        case .failure(let error):
            return Just(Response.badRequest(error.localizedDescription)).eraseToAnyPublisher()
        }
    },

    // Query parameters.
    route(.GET, "/search") { request in
        let query = request.queryParams["q"] ?? ""
        return Just(Response.json(["query": query])).eraseToAnyPublisher()
    },
]

// firstMatch returns a Handler that tries each route in order.
// Falls through to 404 if nothing matches.
let handler = firstMatch(routes)

Thread.detachNewThread {
    _ = startServer(port: 8080).runReader(handler)
}
```

### Path parameters

Segments prefixed with `:` in the pattern are captured into `request.pathParams`:

```swift
// Pattern: /albums/:albumId/photos/:photoId
route(.GET, "/albums/:albumId/photos/:photoId") { request in
    let albumId = request.pathParams["albumId"]!
    let photoId = request.pathParams["photoId"]!
    return Just(Response.html("Album \(albumId), photo \(photoId)")).eraseToAnyPublisher()
}
```

### Query parameters

```swift
// GET /items?page=2&limit=20
route(.GET, "/items") { request in
    let page  = request.queryParams["page"]  ?? "1"
    let limit = request.queryParams["limit"] ?? "10"
    return Just(Response.json(["page": page, "limit": limit])).eraseToAnyPublisher()
}
```

### Body decoding

```swift
struct CreateUser: Decodable {
    let name: String
    let email: String
}

route(.POST, "/users") { request in
    switch request.decodeBody(as: CreateUser.self) {
    case .success(let payload):
        let user = User(id: UUID(), name: payload.name, email: payload.email)
        return Just(Response.json(user, status: .created)).eraseToAnyPublisher()
    case .failure:
        return Just(Response.badRequest("Invalid JSON body")).eraseToAnyPublisher()
    }
}
```

### Composing handlers

Because `Handler` is a `FunctionWrapper`, you can compose middleware as plain function wrappers:

```swift
// Logging middleware: wraps any Handler.
func logged(_ handler: Handler) -> Handler {
    Handler { request in
        print("→ \(request.method) \(request.path)")
        return handler(request).handleEvents(receiveOutput: { response in
            print("← \(response.status.code)")
        }).eraseToAnyPublisher()
    }
}

// Auth middleware: rejects requests without a token.
func authenticated(_ handler: Handler) -> Handler {
    Handler { request in
        guard request.queryParams["token"] == "secret" else {
            return Just(Response(status: .unauthorized)).eraseToAnyPublisher()
        }
        return handler(request)
    }
}

let handler = logged(authenticated(firstMatch(routes)))
_ = startServer(port: 8080).runReader(handler)
```

### Integrating with HTMLTemplating

`NetworkServer` and `HTMLTemplating` compose naturally — run the `Reader` from `render` inside a route handler:

```swift
let env = HTMLEnvironment(fragmentsDir: "/app/templates")

let routes: [RouteMatcher] = [
    route(.GET, "/") { _ in
        let ctx: Context = [
            "title": .string("Home"),
            "items": .list([
                ["name": .string("First")],
                ["name": .string("Second")],
            ]),
        ]
        switch render("{{#include page}}", ctx).runReader(env) {
        case .success(let html):
            return Just(Response.html(html)).eraseToAnyPublisher()
        case .failure(let error):
            return Just(Response.serverError(String(describing: error))).eraseToAnyPublisher()
        }
    },
]
```

---

## Design principles

All three packages follow the same functional conventions via [`FP`](https://github.com/luizmb/FP):

- **`Reader`** for dependency injection (fragment directory, server handler). No `init` injection, no stored globals.
- **`Result`** instead of `throws` at all public API boundaries. Errors are values.
- **`Publisher`** (Combine) instead of `async`/`await`. Composable, cancellable, backpressure-aware.
- **`FunctionWrapper`** for any `(A) -> B` that should be composable — `Handler`, `RequestPublisher`, `DecoderResult` all conform.
- **No crashing operations** — no force-unwrap, no `fatalError`, no `try!`. All failure paths return `Result` or `Publisher` errors.
