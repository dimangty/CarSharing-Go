//
//  GRPCLoggingInterceptor.swift
//  Client
//
//  Created by dmitry on 03.11.2026.
//

#if DEBUG
import Foundation
import GRPCCore
import SwiftProtobuf

struct GRPCLoggingInterceptor: ClientInterceptor {
    let output: @Sendable (String) -> Void

    init(output: @escaping @Sendable (String) -> Void = { print($0) }) {
        self.output = output
    }

    func intercept<Input: Sendable, Output: Sendable>(
        request: StreamingClientRequest<Input>,
        context: ClientContext,
        next: @concurrent (StreamingClientRequest<Input>, ClientContext) async throws -> StreamingClientResponse<Output>
    ) async throws -> StreamingClientResponse<Output> {
        let id = UUID().uuidString
        let method = context.descriptor.fullyQualifiedMethod
        let started = ContinuousClock.now
        let output = output
        output("[gRPC] id=\(id) event=start method=\(method)")
        let finish: @Sendable (String) -> Void = { status in
            let elapsed = started.duration(to: .now).components
            let milliseconds = Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
            let duration = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), milliseconds)
            output("[gRPC] id=\(id) event=end method=\(method) status=\(status) duration_ms=\(duration)")
        }

        var request = request
        let producer = request.producer
        request.producer = { writer in
            try await producer(RPCWriter(wrapping: LoggedRequestWriter(base: writer) { message in
                output("[gRPC] id=\(id) event=request method=\(method)\n\(Self.payload(for: message))")
            }))
        }

        do {
            var response = try await next(request, context)
            switch response.accepted {
            case .failure(let error):
                finish(Self.status(for: error))
            case .success(var contents):
                // Headers only mean the RPC was accepted. Its final status arrives
                // while consuming the body, including errors after a message.
                contents.bodyParts = RPCAsyncSequence(wrapping: LoggedResponseBody(
                    base: contents.bodyParts,
                    logMessage: { message in
                        output("[gRPC] id=\(id) event=response method=\(method)\n\(Self.payload(for: message))")
                    },
                    finish: finish
                ))
                response.accepted = .success(contents)
            }
            return response
        } catch {
            finish(Self.status(for: error))
            throw error
        }
    }

    private static func payload<Message>(for message: Message) -> String {
        guard let message = message as? any SwiftProtobuf.Message else { return "<payload_unavailable>" }
        do {
            let object = try JSONSerialization.jsonObject(with: message.jsonUTF8Data(), options: .fragmentsAllowed)
            let data = try JSONSerialization.data(
                withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes]
            )
            return String(decoding: data, as: UTF8.self)
        } catch {
            // Diagnostic formatting must never prevent a message from being sent or received.
            return "<payload_unavailable>"
        }
    }

    static func status(for error: any Error) -> String {
        if let error = error as? RPCError { return String(describing: error.code) }
        if error is CancellationError { return "cancelled" }
        // Error messages and causes may contain credentials or server payloads.
        return "unexpected"
    }
}

private struct LoggedRequestWriter<Element: Sendable>: RPCWriterProtocol {
    let base: RPCWriter<Element>
    let logMessage: @Sendable (Element) -> Void

    func write(_ element: Element) async throws {
        logMessage(element)
        try await base.write(element)
    }

    func write(contentsOf elements: some Sequence<Element>) async throws {
        for element in elements { try await write(element) }
    }
}

private struct LoggedResponseBody<Message: Sendable>: AsyncSequence, Sendable {
    typealias Element = StreamingClientResponse<Message>.Contents.BodyPart
    let base: RPCAsyncSequence<Element, any Error>
    let logMessage: @Sendable (Message) -> Void
    let finish: @Sendable (String) -> Void

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(base: base.makeAsyncIterator(), logMessage: logMessage, finish: finish)
    }

    struct AsyncIterator: AsyncIteratorProtocol {
        var base: RPCAsyncSequence<Element, any Error>.AsyncIterator
        let logMessage: @Sendable (Message) -> Void
        let finish: @Sendable (String) -> Void
        var receivedTrailers = false
        var completed = false

        mutating func next() async throws -> Element? {
            try await next(isolation: nil)
        }

        mutating func next(isolation actor: isolated (any Actor)?) async throws -> Element? {
            do {
                let part = try await base.next(isolation: actor)
                if case .message(let message)? = part { logMessage(message) }
                if case .trailingMetadata? = part { receivedTrailers = true }
                if part == nil, !completed {
                    completed = true
                    finish(receivedTrailers ? "ok" : "incomplete")
                }
                return part
            } catch {
                if !completed {
                    completed = true
                    finish(GRPCLoggingInterceptor.status(for: error))
                }
                throw error
            }
        }
    }
}
#endif
