# ``Core``

Shared foundations for the NetworkTools suite — the `Convert` codec layer (`DataEncoder` /
`DataDecoder` and their factories) every other package builds on.

## Overview

**NetworkTools** is a suite of composable Swift networking packages built on functional programming
principles (via [`FP`](https://github.com/luizmb/FP)): `Reader` for dependency injection, `Result`
for errors, ReactiveConcurrency's `Publisher` for async, and `FunctionWrapper` for composable functions.
No force-unwraps, no `fatalError`, no silent failures.

`Core` is the base module. The suite's other products layer on top of it:

| Product | Purpose |
|---|---|
| `HTMLTemplating` | File-based HTML template engine with `{{}}` directives |
| `NetworkClient` | Composable HTTP client over `URLSession` |
| `NetworkServer` | Embedded swift-nio HTTP server with a typed routing DSL (Posix platforms) |
| `WebSocketClient` | Full-duplex WebSocket client |
| `Multipeer` / `BonjourService` | Apple-only peer discovery and connectivity |

See the [platform-support matrix](https://github.com/luizmb/NetworkTools#platform-support) — not
every product is available on every platform.

## Topics

### Getting Started
- <doc:GettingStarted>
