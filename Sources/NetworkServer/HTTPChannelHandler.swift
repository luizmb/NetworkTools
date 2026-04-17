import Combine
import Foundation
import NIOCore
import NIOHTTP1

public final class HTTPChannelHandler: ChannelInboundHandler, @unchecked Sendable {
    public typealias InboundIn   = HTTPServerRequestPart
    public typealias OutboundOut = HTTPServerResponsePart

    private let handle: Handler
    private var method: HTTPMethod = .GET
    private var uri:    String     = "/"
    private var body:   [UInt8]    = []
    private var pendingResponse: AnyCancellable?

    public init(handle: Handler) {
        self.handle = handle
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let head):
            method = head.method
            uri    = head.uri
            body   = []
        case .body(var buf):
            body.append(contentsOf: buf.readBytes(length: buf.readableBytes) ?? [])
        case .end:
            let request = Request(method: method, uri: uri, body: Data(body))
            pendingResponse = handle(request)
                .sink { [weak self] response in
                    guard let self else { return }
                    context.eventLoop.execute {
                        self.writeResponse(response, context: context)
                        self.pendingResponse = nil
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

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}
