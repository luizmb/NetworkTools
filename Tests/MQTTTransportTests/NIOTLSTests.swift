// SPDX-License-Identifier: Apache-2.0

#if canImport(NIOPosix)
import FP
import MQTT
import MQTTBroker
import MQTTClient
import MQTTNIO
import MQTTWebSocket
import NIOCore
import NIOPosix
import NIOSSL
import ReactiveConcurrency
import Testing
import WebSocketClient
import WebSocketClientNIO

// A throwaway self-signed certificate for `localhost`, generated for these tests only. Valid from 2020 to
// 2100, so an emulator or CI machine with a skewed clock still accepts it.
private let certificatePEM = """
-----BEGIN CERTIFICATE-----
MIIBdDCCARqgAwIBAgIUFkP41NDx1JcmWurL6Arq0BwBqKkwCgYIKoZIzj0EAwIw
FDESMBAGA1UEAwwJbG9jYWxob3N0MCAXDTIwMDEwMTAwMDAwMFoYDzIxMDAwMTAx
MDAwMDAwWjAUMRIwEAYDVQQDDAlsb2NhbGhvc3QwWTATBgcqhkjOPQIBBggqhkjO
PQMBBwNCAASnfb2UwdP98Gn0e5D5dVPXbz3YHkXx5AM6BhgbB40GzUwMBNcb2gtZ
aVpegkpN7P7K1I5ycYNmLJJq/8WEHVANo0gwRjAdBgNVHQ4EFgQUpwdbleEkTDZV
ERw5/bklwVrJntUwDwYDVR0TAQH/BAUwAwEB/zAUBgNVHREEDTALgglsb2NhbGhv
c3QwCgYIKoZIzj0EAwIDSAAwRQIgI820a0iZG8WQToIcnFlxRTeuvyqyAAM23Ktb
NmCynScCIQCfAjaP0HYbdDEyRxZA8jsD5+FTk0fOesN2zXkzczsBDQ==
-----END CERTIFICATE-----
"""

private let privateKeyPEM = """
-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgqJlBF3dMzbxoK+6A
LBCqy2zt8zaz4vqO68zKRBakL2GhRANCAASnfb2UwdP98Gn0e5D5dVPXbz3YHkXx
5AM6BhgbB40GzUwMBNcb2gtZaVpegkpN7P7K1I5ycYNmLJJq/8WEHVAN
-----END PRIVATE KEY-----
"""

private let tlsTicks: @Sendable () -> Publisher<Duration, Never> = {
    .monotonicTicks(every: .milliseconds(20), clock: ContinuousClock())
}

@Suite struct NIOTLSTests {
    @Test func clientAndBrokerOverTLS() async throws {
        let certificate = try NIOSSLCertificate(bytes: Array(certificatePEM.utf8), format: .pem)
        let key = try NIOSSLPrivateKey(bytes: Array(privateKeyPEM.utf8), format: .pem)
        var client = TLSConfiguration.makeClientConfiguration()
        client.trustRoots = .certificates([certificate])
        let server = TLSConfiguration.makeServerConfiguration(
            certificateChain: [.certificate(certificate)],
            privateKey: .privateKey(key)
        )

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let world = NIOWorld(group: group)
        let bound = try await bindNIO(tls: server, group: group)
        let broker = MQTTBroker.serve(BrokerOptions(), policy: .open, publications: .empty())
            .runReader(BrokerWorld(listener: bound.listener, clock: tlsTicks))
            .sink(receiveCompletion: { _ in }, receiveValue: { _ in })

        let transport = Transport.nio(host: "localhost", port: bound.port, tls: client).runReader(world)
        let received = try await subscribeAndReceiveRetained(over: transport)
        #expect(received == "secret")

        broker.cancel()
        try await group.shutdownGracefully()
    }

    @Test func untrustedCertificateFailsTheConnection() async throws {
        let certificate = try NIOSSLCertificate(bytes: Array(certificatePEM.utf8), format: .pem)
        let key = try NIOSSLPrivateKey(bytes: Array(privateKeyPEM.utf8), format: .pem)
        let server = TLSConfiguration.makeServerConfiguration(
            certificateChain: [.certificate(certificate)],
            privateKey: .privateKey(key)
        )
        var client = TLSConfiguration.makeClientConfiguration()
        client.trustRoots = .certificates([])

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let world = NIOWorld(group: group)
        let bound = try await bindNIO(tls: server, group: group)
        let broker = MQTTBroker.serve(BrokerOptions(), policy: .open, publications: .empty())
            .runReader(BrokerWorld(listener: bound.listener, clock: tlsTicks))
            .sink(receiveCompletion: { _ in }, receiveValue: { _ in })

        let transport = Transport.nio(host: "localhost", port: bound.port, tls: client).runReader(world)
        let result = await MQTTClient.session(loopbackOptions, requests: .empty())
            .runReader(ClientWorld(transport: transport, clock: { .empty() }))
            .collect()
            .firstResultTask()
            .run()
        guard case .failure? = result else {
            Issue.record("expected the TLS handshake to fail, got \(String(describing: result))")
            return
        }
        broker.cancel()
        try await group.shutdownGracefully()
    }
}

@Suite struct NIOSecureWebSocketTests {
    @Test func clientAndBrokerOverSecureWebSocket() async throws {
        let (server, client) = try tlsPair(trusting: true)
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let bound = try await bindNIOWebSocket(tls: server, group: group)
        let broker = MQTTBroker.serve(BrokerOptions(), policy: .open, publications: .empty())
            .runReader(BrokerWorld(listener: bound.listener, clock: tlsTicks))
            .sink(receiveCompletion: { _ in }, receiveValue: { _ in })

        let transport = Transport.webSocket { secureWebSocket(port: bound.port, tls: client, group: group) }
        let received = try await subscribeAndReceiveRetained(over: transport)
        #expect(received == "secret")

        broker.cancel()
        try await group.shutdownGracefully()
    }

    @Test func untrustedCertificateFailsTheWebSocket() async throws {
        let (server, client) = try tlsPair(trusting: false)
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let bound = try await bindNIOWebSocket(tls: server, group: group)
        let accepting = bound.listener.accept().sink(receiveCompletion: { _ in }, receiveValue: { _ in })

        let result = await secureWebSocket(port: bound.port, tls: client, group: group).firstResultTask().run()
        guard case .failure(.connectionFailed)? = result else {
            Issue.record("expected the TLS handshake to fail, got \(String(describing: result))")
            return
        }
        accepting.cancel()
        try await group.shutdownGracefully()
    }
}

/// The server configuration for the test certificate, and a client that trusts it (or nothing).
private func tlsPair(trusting: Bool) throws -> (server: TLSConfiguration, client: TLSConfiguration) {
    let certificate = try NIOSSLCertificate(bytes: Array(certificatePEM.utf8), format: .pem)
    let key = try NIOSSLPrivateKey(bytes: Array(privateKeyPEM.utf8), format: .pem)
    var client = TLSConfiguration.makeClientConfiguration()
    client.trustRoots = .certificates(trusting ? [certificate] : [])
    let server = TLSConfiguration.makeServerConfiguration(certificateChain: [.certificate(certificate)], privateKey: .privateKey(key))
    return (server, client)
}

/// A `wss://` connection to `localhost` on a loopback port.
private func secureWebSocket(
    port: Int,
    tls: TLSConfiguration,
    group: any EventLoopGroup
) -> Publisher<WebSocketConnection, WebSocketNIOError> {
    WebSocketConnection
        .nio(host: "localhost", port: port, path: "/mqtt", protocols: ["mqtt"], maximumMessageSize: 1 << 16, tls: tls)
        .runReader(WebSocketNIOWorld(group: group, random: SplitMix64(seed: 3)))
}

/// Publishes a retained message and subscribes to it in one session; returns the payload received.
private func subscribeAndReceiveRetained(over transport: Transport) async throws -> String? {
    let name = try #require(TopicName(rawValue: "tls/test"))
    let topicFilter = try #require(TopicFilter(rawValue: "tls/+"))
    let requests: [ClientRequest] = [
        .publish(OutgoingMessage(topic: name, payload: Array("secret".utf8), qos: .atLeastOnce, retain: true, properties: [])),
        .subscribe([Subscription(filter: topicFilter, options: .qos(.atMostOnce))], properties: []),
    ]
    let world = ClientWorld(transport: transport, clock: { .monotonicTicks(every: .milliseconds(20), clock: ContinuousClock()) })
    let result = await MQTTClient.session(loopbackOptions, requests: requests.publisher)
        .runReader(world)
        .compactMap { event -> String? in
            guard case let .message(publish) = event else { return nil }
            return String(bytes: publish.payload, encoding: .utf8)
        }
        .prefix(1)
        .firstResultTask()
        .run()
    return try result?.get()
}
#endif
