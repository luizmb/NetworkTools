import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import FP
import ReactiveConcurrency
import ReactiveConcurrencyTransformers

/// HTTP response task: `Reader<URLRequest, Publisher<A, HTTPError>>` — a `ReaderTPublisher`.
///
/// Feeds a `URLRequest` (environment) to produce a typed async `Publisher`. Compose with
/// `.mapT` / `.flatMapT` / `>=>`; bridge to a SwiftRex `Effect` with `.asEffect` only at the boundary.
public typealias NetworkTask<A: Sendable> = Reader<URLRequest, Publisher<A, HTTPError>>

/// Raw HTTP response: data + metadata from `URLSession`.
public typealias TaskRequester = NetworkTask<(Data, HTTPURLResponse)>
