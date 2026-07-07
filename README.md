# NetworkTools

[![CI](https://github.com/luizmb/NetworkTools/actions/workflows/ci.yml/badge.svg)](https://github.com/luizmb/NetworkTools/actions/workflows/ci.yml)
[![Documentation](https://img.shields.io/badge/docs-online-blue)](https://ios.lu/NetworkTools)
[![Swift 6.3+](https://img.shields.io/badge/swift-6.3%2B-orange)](https://swift.org)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue)](LICENSE)

**[→ Full API Documentation](https://ios.lu/NetworkTools)**

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

## Platform Support

Not every product is available on every platform. `Core` and `HTMLTemplating` are pure
Swift + `FP` and run everywhere; the others depend on platform-specific technologies.

| Product | Apple (macOS/iOS/tvOS/watchOS/visionOS) | Linux | Windows | Notes |
|---|:---:|:---:|:---:|---|
| **Core** | ✅ | ✅ | ✅ | Pure `FP` + Foundation |
| **HTMLTemplating** | ✅ | ✅ | ✅ | Pure `FP` + Foundation |
| **NetworkClient** | ✅ | ✅ | ⚠️ | `URLSession` / `FoundationNetworking` — limited on Windows |
| **WebSocketClient** | ✅ | ✅ | ⚠️ | Uses `URLSessionWebSocketTask` where available |
| **NetworkServer** | ✅ | ✅ | ❌ | Built on swift-nio `NIOPosix` (Posix-only; the NIO dependencies are gated out of Windows in `Package.swift`) |
| **Multipeer** | ✅ (Apple only) | ❌ | ❌ | `MultipeerConnectivity` — Apple frameworks only |
| **BonjourService** | ✅ (Apple only) | ❌ | ❌ | `MultipeerConnectivity` / `Network` — Apple frameworks only |

On non-Apple platforms the Apple-only modules compile to empty (`#if canImport(...)` gated), so
depending on them is safe — they simply expose no API there. CI builds the portable products
(`Core`, `HTMLTemplating`) on Windows.

---

## Installation

```swift
// Package.swift
.package(url: "https://github.com/luizmb/NetworkTools.git", from: "0.6.0")
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

A composable, functional HTTP client built on a single requester type — `HTTPClient` — plus pure decorators for mocking, recording, and replaying traffic. Cross-platform (ReactiveConcurrency; no Combine).

### HTTPClient

`HTTPClient` is a pure function `@Sendable (URLRequest) -> Publisher<(Data, HTTPURLResponse), HTTPError>`. Build one with a factory:

```swift
HTTPClient.live(session: .shared)                  // real network
HTTPClient.const(.ok(body: json))                  // a fixed response, built from a StubResponse
HTTPClient.const(.success((data, response)))       // a fixed Result
```

### The typed pipeline

`HTTPClient` returns the raw `(Data, HTTPURLResponse)`; decode on the response `Publisher`:

```swift
let user = HTTPClient.live(session: .shared)(request)
    .validateStatusCode()                          // 2xx -> Data, else .badStatus(code, body)
    .decode(using: JSONDecoder(), type: User.self) // Publisher<User, HTTPError>
```

### Mocking, recording & replaying (decorators)

A decorator is an `Endo<HTTPClient>` — apply it by calling it on a base client, and layer several by **nesting** (`b(a(base))`, where nesting order is execution order):

- **`override(on:use:)`** — route matching requests to another client (a `.const` mock, or a request-derived one). Develop against an endpoint that isn't built yet, or force an empty/500/timeout case.
- **`record(to:)`** — tee every real exchange to a serialized, on-disk `RecordStore` (any encoder: JSON/Plist/XML/YAML; binary IO injected via `BinaryReader`/`BinaryWriter`).
- **`playback(_:)`** — serve recorded responses from a snapshot, **consume-once** (so a polled endpoint replays `pending -> pending -> done`); unmatched requests fall through to the base — turning a flaky shared-staging e2e suite into a deterministic one.
- **`delay(_:when:clock:)`** — add artificial latency to matching responses (injected clock).

```swift
let client = HTTPClient.override(
    on: .method("GET") && .path("/currencies"),
    use: .const(.json(["MXN", "ARS", "COP", "BRL"], encoder: JSONEncoder()))
)(HTTPClient.live(session: .shared))
```

Two composable atoms drive the decorators: `RequestMatch` (`.method`/`.path`/`.query`/`.header`/`.pathRegex`, combined with `&&`/`||`/`!`) and `StubResponse` (`.ok`/`.status`/`.json`/`.failure` + `.withStatus`/`.withHeader`/`.withBody`, composed with `<>`). See the [Mocking, Recording & Replaying](https://ios.lu/NetworkTools/documentation/networkclient/mockingrecordingreplaying) guide for the full walkthrough.

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
conn.close()
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
