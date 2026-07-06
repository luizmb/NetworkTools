// SPDX-License-Identifier: Apache-2.0

import Foundation
import FP
@preconcurrency import NIOCore
import NIOHTTP1
import ReactiveConcurrency

final class HTTPChannelHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let requestHandler: @Sendable (Request) -> Publisher<Response, ResponseError>
    private var method: HTTPMethod = .GET
    private var uri: String = "/"
    private var body: [UInt8] = []

    init(_ requestHandler: @escaping @Sendable (Request) -> Publisher<Response, ResponseError>) {
        self.requestHandler = requestHandler
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case let .head(head):
            method = head.method
            uri = head.uri
            body = []
        case var .body(buf):
            body.append(contentsOf: buf.readBytes(length: buf.readableBytes) ?? [])
        case .end:
            let request = Request(method: method, uri: uri, body: Data(body))
            let publisher = requestHandler(request)
            let eventLoop = context.eventLoop
            Task { [weak self] in
                guard let self else { return }
                // `.asEffect`-analog for the server boundary: run the response `Publisher` to its
                // first result. A handler that emits nothing (`nil`) is a server-side bug → 500.
                let response: Response = switch await publisher.firstResultTask().run() {
                case let .success(r)?: r
                case let .failure(e)?: Response(e)
                case nil: Response(.serverError("Handler produced no response"))
                }
                eventLoop.execute { [weak self] in
                    guard let self else { return }
                    writeResponse(response, context: context)
                }
            }
        }
    }

    private func writeResponse(_ response: Response, context: ChannelHandlerContext) {
        var headers = HTTPHeaders()
        response.headers.forEach { name, value in headers.add(name: name, value: value) }
        headers.add(name: "Content-Length", value: "\(response.body.count)")

        let head = HTTPResponseHead(version: .http1_1, status: response.status, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)

        var buf = context.channel.allocator.buffer(capacity: response.body.count)
        buf.writeBytes(response.body)
        context.write(wrapOutboundOut(.body(.byteBuffer(buf))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}
