# ``NetworkClient``

A composable, functional HTTP client — one requester type, with pure decorators for mocking,
recording, and deterministically replaying network traffic.

## Overview

``HTTPClient`` is the single requester abstraction: a pure function
`@Sendable (URLRequest) -> Publisher<(Data, HTTPURLResponse), HTTPError>` (ReactiveConcurrency).
`URLRequest` is an ordinary value, so it's a plain function wrapper — not a `Reader`. Behaviour is
layered on with **decorators** — `Endo<HTTPClient>` values applied by calling them on a base and
nesting to compose:

```swift
let client = HTTPClient.record(to: store)(              // …then record everything
    HTTPClient.override(on: .path("/mocked"),           // mock one endpoint…
                        use: .const(.ok(body: json)))(
        HTTPClient.live(session: .shared)
    )
)

// The typed pipeline lives on the response Publisher:
let user = client(request).validateStatusCode().decode(using: JSONDecoder(), type: User.self)
```

Two small, stack-agnostic atoms are shared by the decorators: ``RequestMatch`` (which request) and
``StubResponse`` (what response, composed with `<>`).

## Topics

### Getting Started
- <doc:MockingRecordingReplaying>

### The client
- ``HTTPClient``
- ``HTTPError``

### Decorator atoms
- ``RequestMatch``
- ``StubResponse``

### Recording & replaying
- ``RecordStore``
- ``RequestPlayback``
- ``RecordedExchange``
- ``BinaryReader``
- ``BinaryWriter``
