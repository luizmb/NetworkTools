// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Failure of an injected binary read/write. Errors are surfaced (never swallowed) so callers can react.
public enum FileIOError: Error, Sendable, Equatable {
    case read(String)
    case write(String)
}

/// Reads the bytes at a URL. Injected so persistence stays pure and testable (no ambient filesystem).
public typealias BinaryReader = @Sendable (URL) -> Result<Data, FileIOError>

/// Writes bytes to a URL. Injected for the same reason.
public typealias BinaryWriter = @Sendable (Data, URL) -> Result<Void, FileIOError>

/// Default filesystem-backed implementations. These are the deliberate *system boundary* — inject
/// your own closures (in-memory, sandboxed, encrypted, …) anywhere you need determinism or isolation.
public enum BinaryIO {
    public static let read: BinaryReader = { url in
        Result(catching: { try Data(contentsOf: url) }).mapError { .read($0.localizedDescription) }
    }

    public static let write: BinaryWriter = { data, url in
        Result(catching: {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }).mapError { .write($0.localizedDescription) }
    }
}
