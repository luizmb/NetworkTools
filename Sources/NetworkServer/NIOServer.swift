import Foundation
import FP
import NIOCore
import NIOHTTP1
import NIOPosix

/// Returns a `Reader` that, when run with an `Env`, starts the HTTP server
/// on `host:port` and blocks until the server shuts down or an error occurs.
///
/// Usage:
/// ```swift
/// startServer(port: 8080, router: myRouter).runReader(myEnv)
/// ```
public func startServer<Env: Sendable>(host: String = "127.0.0.1", port: Int, router: Router<Env>) -> Reader<Env, Result<Void, Error>> {
    Reader { env in
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let requestHandler = SendableHandler(call: { router.handle.run($0).run(env) })

        let result = Result<Void, Error> {
            let bootstrap = ServerBootstrap(group: group)
                .serverChannelOption(ChannelOptions.backlog, value: 256)
                .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .childChannelInitializer { channel in
                    channel.pipeline.configureHTTPServerPipeline().flatMap {
                        channel.pipeline.addHandler(HTTPChannelHandler(requestHandler.call))
                    }
                }
                .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)

            let channel = try bootstrap.bind(host: host, port: port).wait()
            print("[NetworkServer] Listening on http://\(host):\(port)")
            try channel.closeFuture.wait()
        }

        if case .failure(let shutdownError) = Result(catching: { try group.syncShutdownGracefully() }) {
            print("[NetworkServer] Event loop shutdown error: \(shutdownError)")
        }

        return result
    }
}
