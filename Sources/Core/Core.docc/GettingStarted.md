# Getting Started

Add NetworkTools and pick the products you need.

## Installation

Add the package to your `Package.swift`:

```swift
.package(url: "https://github.com/luizmb/NetworkTools.git", from: "0.7.0")
```

Each capability is a separate product — depend only on what you use:

```swift
.target(name: "MyApp", dependencies: [
    .product(name: "Core",            package: "NetworkTools"),
    .product(name: "HTMLTemplating",  package: "NetworkTools"),
    .product(name: "NetworkClient",   package: "NetworkTools"),
    .product(name: "NetworkServer",   package: "NetworkTools"),
    .product(name: "WebSocketClient", package: "NetworkTools"),
    .product(name: "BonjourService",  package: "NetworkTools"),
])
```

## Design

Every public API is built on functional foundations from [`FP`](https://github.com/luizmb/FP):

- **`Reader`** for dependency injection — effects (filesystem, network, clock) are injected, never
  reached for ambiently.
- **`Result`** for error handling — no `throws`, no silent failures.
- **`Publisher`** (ReactiveConcurrency) for async work — cold, lazy, and composable.

## Platform availability

Not every product runs on every platform. `Core` and `HTMLTemplating` are pure Swift + `FP` and run
everywhere; `NetworkServer` needs Posix (swift-nio), and `Multipeer` / `BonjourService` are Apple-only.
See the [platform-support matrix](https://github.com/luizmb/NetworkTools#platform-support) for the
full breakdown.

## Per-package guides

Each package has a detailed guide with worked examples in the
[README](https://github.com/luizmb/NetworkTools#packages): HTMLTemplating, NetworkClient,
NetworkServer, WebSocketClient, Multipeer, and BonjourService.
