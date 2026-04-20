import Foundation
import FP
@preconcurrency import NIOCore
import NIOHTTP1

final class HTTPChannelHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn   = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let requestHandler: (Request) -> DeferredTask<Result<Response, ResponseError>>
    private var method: HTTPMethod = .GET
    private var uri: String = "/"
    private var body: [UInt8] = []

    init(_ requestHandler: @escaping (Request) -> DeferredTask<Result<Response, ResponseError>>) {
        self.requestHandler = requestHandler
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let head):
            method = head.method
            uri    = head.uri
            body   = []
        case .body(var buf):
            body.append(contentsOf: buf.readBytes(length: buf.readableBytes) ?? [])
        case .end:
            let request   = Request(method: method, uri: uri, body: Data(body))
            let task      = requestHandler(request)
            let eventLoop = context.eventLoop
            Task { [weak self] in
                guard let self else { return }
                let response = switch await task.run() {
                case .success(let r): r
                case .failure(let e): Response(e)
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
