# ``NetworkClient``

A composable, functional HTTP client — and a set of pure decorators for mocking, recording, and
deterministically replaying network traffic.

## Overview

The client is a plain function: `@Sendable (URLRequest) -> Publisher<(Data, HTTPURLResponse), HTTPError>`,
wrapped as ``HTTPRequester`` (ReactiveConcurrency) or ``Requester`` (Combine). Because it's *just a
function*, behaviour is layered on with **decorators** — `Endo<HTTPRequester>` values that compose:

Each decorator is an `Endo<HTTPRequester>` — a callable value. Apply one by calling it on a base;
layer several by **nesting**, which keeps the order of execution explicit (base first, inside-out):

```swift
let client = HTTPRequester.recording(to: store)(   // …then capture everything, mocks included
    HTTPRequester.overriding(rules)(               // base is overridden first…
        URLSession.shared.httpRequester
    )
)
```

Two small, stack-agnostic atoms are shared by every decorator:

- ``RequestMatch`` — "which request?", a composable `(URLRequest) -> Bool`.
- ``StubResponse`` — "what response?", a composable `Endo` over the `Result` with sensible defaults.

## Topics

### Getting Started
- <doc:MockingRecordingReplaying>

### The requester
- ``HTTPRequester``
- ``HTTPError``

### Decorator atoms
- ``RequestMatch``
- ``StubResponse``

### Decorators
- ``Rule``
- ``RecordStore``
- ``RequestPlayback``
- ``ReplayFallback``
- ``RecordedExchange``
