// SPDX-License-Identifier: Apache-2.0

#if canImport(Network) && canImport(NIOPosix)
import Dispatch
import MQTT
import MQTTNWConnection
import NIOCore
import NIOPosix
import Testing

@Suite struct NWConnectionTransportTests {
    @Test func clientSessionOverLoopbackTCP() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let server = try await startBroker(group)
        let port = try #require(server.localAddress?.port.flatMap(UInt16.init(exactly:)))
        let transport = Transport.nwConnection(host: "127.0.0.1", port: port, parameters: .tcp)
            .runReader(NWWorld(queue: DispatchQueue(label: "mqtt-nw-test")))

        let received = try await subscribeAndReceive(over: transport)
        #expect(received.count == 3)
        #expect(lastPayload(received) == Array("hello".utf8))

        try await server.close().get()
        try await group.shutdownGracefully()
    }

    @Test func refusedConnectionIsTyped() async {
        let transport = Transport.nwConnection(host: "127.0.0.1", port: 1, parameters: .tcp)
            .runReader(NWWorld(queue: DispatchQueue(label: "mqtt-nw-refused")))
        let result = await transport.connect().firstResultTask().run()
        guard case .failure(.connectionFailed) = result else {
            Issue.record("expected connectionFailed, got \(String(describing: result))")
            return
        }
    }
}
#endif
