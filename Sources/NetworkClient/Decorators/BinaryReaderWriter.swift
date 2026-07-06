// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Failure of a ``BinaryReader``.
public enum ReadError: Error, Sendable, Equatable {
    case failed(String)
}

/// Failure of a ``BinaryWriter``.
public enum WriteError: Error, Sendable, Equatable {
    case failed(String)
}

/// Reads the bytes at a URL. A tiny injected effect so persistence stays pure and testable — inject
/// an in-memory / sandboxed / encrypted reader anywhere you need determinism or isolation. Only the
/// replay path needs a reader; only the record path needs a writer — inject either or both.
public struct BinaryReader: Sendable {
    public let read: @Sendable (URL) -> Result<Data, ReadError>

    public init(_ read: @escaping @Sendable (URL) -> Result<Data, ReadError>) {
        self.read = read
    }

    public func callAsFunction(_ url: URL) -> Result<Data, ReadError> { read(url) }

    /// Filesystem-backed reader — the deliberate system boundary.
    public static let fileManager = BinaryReader { url in
        Result(catching: { try Data(contentsOf: url) }).mapError { .failed($0.localizedDescription) }
    }
}

/// Writes bytes to a URL. Injected for the same reason as ``BinaryReader``.
public struct BinaryWriter: Sendable {
    public let write: @Sendable (Data, URL) -> Result<Void, WriteError>

    public init(_ write: @escaping @Sendable (Data, URL) -> Result<Void, WriteError>) {
        self.write = write
    }

    public func callAsFunction(_ data: Data, _ url: URL) -> Result<Void, WriteError> { write(data, url) }

    /// Filesystem-backed writer — creates intermediate directories and writes atomically.
    public static let fileManager = BinaryWriter { data, url in
        Result(catching: {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }).mapError { .failed($0.localizedDescription) }
    }
}
