# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.6.0] - 2026-07-05

### Added
- `WebSocketClient` and `BonjourService` products.
- Bonjour APIs: `bonjourBrowserStream(browser:)`, `bonjourResolve`, and a `ServiceDescription` bridge.

### Changed
- Migrated the async surface from ZIO to `Reader<Env, Publisher>` with `DeferredTask` / `Publisher`.
- `WebSocketConnection` and `BonjourConnection` are now classes with ARC-managed lifetimes.
- Swift 6.3 / Xcode 26.5; test suites migrated to `Reader<Env, Publisher>`.

## [0.5.0] - 2026-05-21

### Added
- `NetworkServer` — embedded swift-nio HTTP server with a typed functional routing DSL.

## [0.4.0] - 2026-05-18

### Added
- `Multipeer` and the core HTTP client/templating packages.

## [0.1.0] - 2026-04-24

- Initial release.

[Unreleased]: https://github.com/luizmb/NetworkTools/compare/v0.6.0...main
[0.6.0]: https://github.com/luizmb/NetworkTools/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/luizmb/NetworkTools/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/luizmb/NetworkTools/compare/v0.1.0...v0.4.0
[0.1.0]: https://github.com/luizmb/NetworkTools/releases/tag/v0.1.0
