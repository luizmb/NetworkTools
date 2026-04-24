import Foundation
import FP

/// HTTP response task: uses a `URLRequest` as environment to produce a typed async result.
///
/// `NetworkTask<A>` = `ZIO<URLRequest, A, HTTPError>`:
///   `(URLRequest) -> DeferredTask<Result<A, HTTPError>>`
public typealias NetworkTask<A: Sendable> = ZIO<URLRequest, A, HTTPError>

/// Raw HTTP response: data + metadata from `URLSession`.
public typealias TaskRequester = NetworkTask<(Data, HTTPURLResponse)>
