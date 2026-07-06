// SPDX-License-Identifier: Apache-2.0

import Core
import Foundation

/// Specifies how to decode a typed value from a `[String: String]` dictionary
/// (URL path params or query string) within environment `Env`.
///
/// Construct via the static factories — never directly:
/// - `.ignore`                               — always succeeds with `Empty`, pins `T = Empty`
/// - `.decode(using: \.myDecoder)`           — lens to `DictionaryDecoder<T>` on `Env`
/// - `.decode(MyType.self, using: \.factory)` — lens to `DictionaryDecoderFactory` on `Env`
public struct RouteParam<T: Decodable & Sendable, Env: Sendable>: Sendable {
    let run: @Sendable (Env, [String: String]) -> Result<T, DecodingError>
}

public extension RouteParam where T == Empty {
    static var ignore: Self {
        RouteParam { _, _ in .success(.value) }
    }
}

public extension RouteParam {
    static func decode(
        using lens: @escaping @Sendable (Env) -> DictionaryDecoder<T>
    ) -> Self {
        RouteParam { env, dict in lens(env).run(dict) }
    }

    static func decode(
        _ type: T.Type = T.self,
        using factory: @escaping @Sendable (Env) -> DictionaryDecoderFactory
    ) -> Self {
        RouteParam { env, dict in factory(env).dictionaryDecoder(for: T.self).run(dict) }
    }
}
