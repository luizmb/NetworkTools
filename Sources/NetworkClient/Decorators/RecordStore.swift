// SPDX-License-Identifier: Apache-2.0

import Core
import Foundation
import FP

/// A serialized, on-disk store of recorded exchanges — the persistence behind the record decorator.
///
/// `RecordStore` is an `actor`, so concurrent requests recording at the same time can never interleave
/// their read-modify-write (the race ARQ's `struct` recorder documented and accepted). It keeps an
/// in-memory copy so it doesn't re-read the whole file per exchange, and every mutation returns a
/// `Result` — write and encode failures are surfaced, not swallowed.
///
/// Encoding/decoding go through any `DataEncoderFactory` / `DataDecoderFactory` (JSON, Plist, XML,
/// YAML…); the concrete coder is derived once at init so the (non-Sendable) factory never crosses the
/// actor boundary.
public actor RecordStore {
    private let url: URL
    private let read: BinaryReader
    private let write: BinaryWriter
    private let encode: DataEncoder<[RecordedExchange]>
    private let decode: DataDecoder<[RecordedExchange]>
    private var cache: [RecordedExchange] = []
    private var loaded = false

    public init(
        url: URL,
        read: @escaping BinaryReader = BinaryIO.read,
        write: @escaping BinaryWriter = BinaryIO.write,
        encoder: some DataEncoderFactory & Sendable,
        decoder: some DataDecoderFactory & Sendable
    ) {
        self.url = url
        self.read = read
        self.write = write
        encode = encoder.dataEncoder(for: [RecordedExchange].self)
        decode = decoder.dataDecoder(for: [RecordedExchange].self)
    }

    /// All recorded exchanges (loads + caches on first access).
    public func all() -> [RecordedExchange] {
        if loaded { return cache }
        cache = (try? read(url).get()).flatMap { try? decode.run($0).get() } ?? []
        loaded = true
        return cache
    }

    /// Appends an exchange and persists. Call once per response; serialized by the actor.
    @discardableResult
    public func append(_ exchange: RecordedExchange) -> Result<Void, FileIOError> {
        var next = all()
        next.append(exchange)
        return persist(next)
    }

    /// Clears the store (e.g. once at the start of a recording session).
    @discardableResult
    public func reset() -> Result<Void, FileIOError> {
        persist([])
    }

    private func persist(_ exchanges: [RecordedExchange]) -> Result<Void, FileIOError> {
        switch encode.run(exchanges) {
        case let .success(data):
            let result = write(data, url)
            if case .success = result {
                cache = exchanges
                loaded = true
            }
            return result
        case let .failure(error):
            return .failure(.write("encode failed: \(error)"))
        }
    }
}
