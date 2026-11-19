// SPDX-License-Identifier: Apache-2.0

import Core
import FP

/// Splits a byte stream into packets.
///
/// Transports deliver arbitrary chunks: half a packet, three packets and a bit, … A
/// `PacketStream` keeps the bytes not yet forming a whole packet in its buffer and decodes every
/// complete packet each time a chunk arrives. It is a plain value; ``feed(_:)`` is a pure
/// `Stateful` step, so a session can fold it over the incoming chunks.
///
/// ```swift
/// let (packets, stream) = PacketStream(version: .v5, maximumPacketSize: 1 << 20)
///     .feed(chunk)
///     .runStateful(stream)
/// ```
public struct PacketStream: Sendable, Hashable {
    /// The version packets are decoded with.
    public var version: ProtocolVersion
    /// The largest packet accepted, in bytes; a larger Remaining Length fails with
    /// ``PacketStreamError/packetTooLarge(_:maximum:)`` before buffering it.
    public var maximumPacketSize: Int
    /// Bytes received that do not yet form a whole packet.
    public private(set) var buffer: [UInt8]

    /// Creates an empty stream.
    /// - Parameters:
    ///   - version: The version packets are decoded with.
    ///   - maximumPacketSize: The largest packet accepted, in bytes.
    public init(version: ProtocolVersion, maximumPacketSize: Int) {
        self.version = version
        self.maximumPacketSize = maximumPacketSize
        buffer = []
    }

    /// Appends a chunk and decodes every complete packet it finishes.
    /// - Parameter chunk: Bytes just received.
    /// - Returns: A step producing the decoded packets in order, or the first failure.
    public static func feed(_ chunk: [UInt8]) -> Stateful<PacketStream, Result<[Packet], PacketStreamError>> {
        Stateful { stream in
            stream.buffer += chunk
            var packets: [Packet] = []
            while true {
                switch PacketStream.frame(stream.buffer[...], maximumPacketSize: stream.maximumPacketSize) {
                case .success(.none):
                    return .success(packets)
                case let .success(.some(frame)):
                    switch Packet.decode(Array(frame.packet), for: stream.version) {
                    case let .success(packet):
                        packets.append(packet)
                        stream.buffer = Array(frame.rest)
                    case let .failure(error):
                        return .failure(.decoding(error))
                    }
                case let .failure(error):
                    return .failure(error)
                }
            }
        }
    }

    /// Finds the first complete packet in `input`.
    /// - Parameters:
    ///   - input: Buffered bytes, starting at a packet boundary.
    ///   - maximumPacketSize: The largest packet accepted.
    /// - Returns: The packet's bytes and the bytes after it; `nil` when more bytes are needed.
    public static func frame(
        _ input: ByteInput,
        maximumPacketSize: Int
    ) -> Result<(packet: ByteInput, rest: ByteInput)?, PacketStreamError> {
        let header = MQTTParser<UInt8>.byte *> Read.variableByteInteger
        return switch header.parse(input) {
        case let .success((length, body)):
            frame(input, headerSize: input.count - body.count, bodySize: Int(length), maximumPacketSize: maximumPacketSize)
        case .failure(.binary(.unexpectedEnd)):
            .success(nil)
        case let .failure(error):
            .failure(.decoding(error))
        }
    }

    private static func frame(
        _ input: ByteInput,
        headerSize: Int,
        bodySize: Int,
        maximumPacketSize: Int
    ) -> Result<(packet: ByteInput, rest: ByteInput)?, PacketStreamError> {
        let size = headerSize + bodySize
        return size > maximumPacketSize ? .failure(.packetTooLarge(size, maximum: maximumPacketSize))
            : input.count < size ? .success(nil)
            : .success((packet: input.prefix(size), rest: input.dropFirst(size)))
    }
}

/// Why a byte stream could not be split into packets.
public enum PacketStreamError: Error, Sendable, Hashable {
    /// A packet's bytes are invalid.
    case decoding(MQTTDecodingError)
    /// A packet announces more bytes than the configured maximum.
    case packetTooLarge(Int, maximum: Int)
}
