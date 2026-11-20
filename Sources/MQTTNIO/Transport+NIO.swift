// SPDX-License-Identifier: Apache-2.0

#if canImport(NIOPosix)
import FP
import MQTT
import NIOCore
import NIOPosix
import NIOSSL
import ReactiveConcurrency

/// The effects SwiftNIO transports and listeners need, supplied at the application's boundary
/// through `Reader`.
public struct NIOWorld: Sendable {
    /// The event loop group channels run on. The application owns its lifecycle.
    public let group: any EventLoopGroup

    /// Creates a world.
    /// - Parameter group: The event loop group channels run on.
    public init(group: any EventLoopGroup) {
        self.group = group
    }
}

public extension Transport {
    /// A transport over SwiftNIO TCP, optionally TLS (Apple platforms, Linux, Android).
    ///
    /// Every subscription to `Transport/connect` opens a new channel. Inbound bytes are buffered
    /// from the moment the channel is active, so nothing is lost before the session subscribes to
    /// `TransportConnection/receive`.
    ///
    /// ```swift
    /// let world = NIOWorld(group: MultiThreadedEventLoopGroup(numberOfThreads: 1))
    /// let plain = Transport.nio(host: "192.168.1.20", port: 1883, tls: nil).runReader(world)
    /// let secure = Transport.nio(host: "broker.example.com", port: 8883, tls: .makeClientConfiguration()).runReader(world)
    /// ```
    /// - Parameters:
    ///   - host: The broker's host name or IP address (also the TLS server name).
    ///   - port: The broker's TCP port (1883 plain, 8883 TLS).
    ///   - tls: The TLS configuration, or `nil` for plain TCP.
    /// - Returns: The transport, waiting for its world.
    static func nio(host: String, port: Int, tls: TLSConfiguration?) -> Reader<NIOWorld, Transport> {
        Reader { world in
            Transport {
                .future { () async -> Result<TransportConnection, TransportError> in
                    let context: NIOSSLContext?
                    do {
                        context = try tls.map(NIOSSLContext.init(configuration:))
                    } catch {
                        return .failure(.connectionFailed(String(describing: error)))
                    }
                    let (inbound, sink) = AsyncStream<Result<[UInt8], TransportError>>.makeStream()
                    let bootstrap = ClientBootstrap(group: world.group)
                        .channelOption(ChannelOptions.tcpOption(.tcp_nodelay), value: 1)
                        .channelInitializer { channel in
                            channel.eventLoop.makeCompletedFuture {
                                if let context {
                                    try channel.pipeline.syncOperations.addHandler(
                                        NIOSSLClientHandler(context: context, serverHostname: host.isIPAddress ? nil : host)
                                    )
                                }
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
}

private extension String {
    /// IP literals are not valid TLS server names (SNI).
    var isIPAddress: Bool {
        (try? SocketAddress(ipAddress: self, port: 0)) != nil
    }
}

private func openChannel(_ bootstrap: ClientBootstrap, host: String, port: Int) async -> Result<any Channel, TransportError> {
    do {
        return try await .success(bootstrap.connect(host: host, port: port).get())
    } catch {
        return .failure(.connectionFailed(String(describing: error)))
    }
}

func transportConnection(_ channel: any Channel, inbound: AsyncStream<Result<[UInt8], TransportError>>) -> TransportConnection {
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
final class InboundBytes: ChannelInboundHandler, Sendable {
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
