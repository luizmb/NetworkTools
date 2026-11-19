// SPDX-License-Identifier: Apache-2.0

#if canImport(NIOPosix)
import FP
import MQTT
import NIOCore
import NIOPosix
import ReactiveConcurrency

public extension Transport {
    /// A transport over SwiftNIO TCP (Apple platforms and Linux).
    ///
    /// Every subscription to `Transport/connect` opens a new channel on `group`. Inbound
    /// bytes are buffered from the moment the channel is active, so nothing is lost before the
    /// session subscribes to `TransportConnection/receive`.
    ///
    /// ```swift
    /// let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    /// let transport = Transport.nio(host: "192.168.1.20", port: 1883, group: group)
    /// ```
    /// - Parameters:
    ///   - host: The broker's host name or IP address.
    ///   - port: The broker's TCP port.
    ///   - group: The event loop group the channel runs on. Injected so the caller owns its lifecycle.
    /// - Returns: The transport.
    static func nio(host: String, port: Int, group: any EventLoopGroup) -> Transport {
        Transport {
            .future { () async -> Result<TransportConnection, TransportError> in
                let (inbound, sink) = AsyncStream<Result<[UInt8], TransportError>>.makeStream()
                let bootstrap = ClientBootstrap(group: group)
                    .channelOption(ChannelOptions.tcpOption(.tcp_nodelay), value: 1)
                    .channelInitializer { channel in
                        channel.eventLoop.makeCompletedFuture {
                            try channel.pipeline.syncOperations.addHandler(InboundBytes(sink))
                        }
                    }
                return await openChannel(bootstrap, host: host, port: port).map { channel in
                    transportConnection(channel, inbound: inbound)
                }
            }
        }
    }
}

private func openChannel(_ bootstrap: ClientBootstrap, host: String, port: Int) async -> Result<any Channel, TransportError> {
    do {
        return try await .success(bootstrap.connect(host: host, port: port).get())
    } catch {
        return .failure(.connectionFailed(String(describing: error)))
    }
}

private func transportConnection(_ channel: any Channel, inbound: AsyncStream<Result<[UInt8], TransportError>>) -> TransportConnection {
    TransportConnection(
        receive: Publisher<[UInt8], TransportError> { continuation async throws(TransportError) in
            await withTaskCancellationHandler {
                for await chunk in inbound {
                    switch chunk {
                    case let .success(bytes): continuation.yield(bytes)
                    case let .failure(error): return continuation.fail(error)
                    }
                }
                continuation.finish()
            } onCancel: {
                channel.close(promise: nil)
            }
        },
        send: { bytes in
            .future { () async -> Result<Void, TransportError> in
                do {
                    try await channel.writeAndFlush(ByteBuffer(bytes: bytes)).get()
                    return .success(())
                } catch {
                    return .failure(.sendFailed(String(describing: error)))
                }
            }
        },
        close: {
            Publisher<Void, Never> { continuation async throws(Never) in
                channel.close(promise: nil)
                continuation.yield(())
            }
        }
    )
}

/// Forwards every inbound `ByteBuffer` to an `AsyncStream`, then finishes it when the channel goes inactive.
private final class InboundBytes: ChannelInboundHandler, Sendable {
    typealias InboundIn = ByteBuffer

    private let sink: AsyncStream<Result<[UInt8], TransportError>>.Continuation

    init(_ sink: AsyncStream<Result<[UInt8], TransportError>>.Continuation) {
        self.sink = sink
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        sink.yield(.success(buffer.readBytes(length: buffer.readableBytes) ?? []))
    }

    func channelInactive(context: ChannelHandlerContext) {
        sink.finish()
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        sink.yield(.failure(.connectionLost(String(describing: error))))
        sink.finish()
        context.close(promise: nil)
    }
}
#endif
