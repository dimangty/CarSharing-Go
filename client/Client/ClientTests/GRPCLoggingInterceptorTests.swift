import XCTest
import GRPCCore
import Synchronization
#if canImport(Client)
@testable import Client
#else
@testable import ClientAuth
#endif

#if DEBUG
final class GRPCLoggingInterceptorTests: XCTestCase {
    private typealias Response = StreamingClientResponse<String>
    private typealias Part = Response.Contents.BodyPart

    private let context = ClientContext(
        descriptor: MethodDescriptor(fullyQualifiedService: "auth.AuthService", method: "SignIn"),
        remotePeer: "ipv4:127.0.0.1:50051",
        localPeer: "ipv4:127.0.0.1:12345"
    )

    func testLogsUnmaskedProtobufRequestsAndResponsesLazily() async throws {
        let logs = LogCapture()
        let calls = LogCapture()
        let writer = RecordingWriter<Auth_SignInRequest>()
        let interceptor = GRPCLoggingInterceptor(output: { logs.append($0) })
        var signIn = Auth_SignInRequest()
        signIn.userName = "demo\"\nпользователь"
        signIn.userPassword = "PASSWORD_SECRET"
        signIn.userIdentifyString = "ios-device"
        let sent = signIn
        let request = StreamingClientRequest<Auth_SignInRequest>(metadata: ["authorization": "REQUEST_SECRET"]) { writer in
            calls.append("producer")
            try await writer.write(sent)
        }
        var signInResponse = Auth_SignInResponse()
        signInResponse.success = true
        signInResponse.accessToken = "ACCESS_TOKEN_SECRET"
        signInResponse.refreshToken = "REFRESH_TOKEN_SECRET"
        let received = signInResponse
        typealias BodyPart = StreamingClientResponse<Auth_SignInResponse>.Contents.BodyPart
        let body = AsyncThrowingStream<BodyPart, any Error> { continuation in
            continuation.yield(.message(received))
            continuation.yield(.trailingMetadata([:]))
            continuation.finish()
        }

        let response: StreamingClientResponse<Auth_SignInResponse> = try await interceptor.intercept(
            request: request, context: context
        ) { forwarded, _ in
            XCTAssertTrue(calls.lines.isEmpty, "The interceptor must not run the producer ahead of the transport")
            XCTAssertFalse(logs.lines.contains { $0.contains("event=request ") })
            XCTAssertEqual(forwarded.metadata, ["authorization": "REQUEST_SECRET"])
            try await forwarded.producer(RPCWriter(wrapping: writer))
            return StreamingClientResponse(metadata: [:], bodyParts: RPCAsyncSequence(wrapping: body))
        }

        XCTAssertEqual(calls.lines, ["producer"])
        XCTAssertEqual(writer.messages, [sent])
        let requestJSON = try payload(in: logs.lines, event: "request")
        XCTAssertEqual(requestJSON["userName"] as? String, "demo\"\nпользователь")
        XCTAssertEqual(requestJSON["userPassword"] as? String, "PASSWORD_SECRET")
        XCTAssertEqual(requestJSON["userIdentifyString"] as? String, "ios-device")
        XCTAssertFalse(logs.lines.contains { $0.contains("event=response ") })

        var messages: [Auth_SignInResponse] = []
        for try await message in response.messages { messages.append(message) }
        XCTAssertEqual(messages, [received])
        let responseJSON = try payload(in: logs.lines, event: "response")
        XCTAssertEqual(responseJSON["success"] as? Bool, true)
        XCTAssertEqual(responseJSON["accessToken"] as? String, "ACCESS_TOKEN_SECRET")
        XCTAssertEqual(responseJSON["refreshToken"] as? String, "REFRESH_TOKEN_SECRET")
        XCTAssertEqual(logs.lines.count, 4)
        assertLogPair(logs.lines)
        assertNoMetadataOrErrorDetails(logs.lines)
    }

    func testLogsAndForwardsEveryMessageInABatch() async throws {
        let logs = LogCapture()
        let writer = RecordingWriter<Auth_SignUpRequest>()
        let interceptor = GRPCLoggingInterceptor(output: { logs.append($0) })
        let messages = ["first", "second"].map { name in
            var message = Auth_SignUpRequest()
            message.userName = name
            message.userPassword = "PASSWORD_SECRET"
            message.userPasswordConfirm = "PASSWORD_SECRET"
            return message
        }
        let request = StreamingClientRequest<Auth_SignUpRequest> { writer in
            try await writer.write(contentsOf: messages)
        }
        let _: Response = try await interceptor.intercept(request: request, context: context) { forwarded, _ in
            try await forwarded.producer(RPCWriter(wrapping: writer))
            return Response(error: RPCError(code: .unimplemented, message: "ERROR_SECRET"))
        }

        XCTAssertEqual(writer.messages, messages)
        let entries = logs.lines.filter { $0.contains("event=request ") }
        XCTAssertEqual(entries.count, 2)
        let payloads = try entries.map { try payload(in: [$0], event: "request") }
        XCTAssertEqual(payloads.compactMap { $0["userName"] as? String }, ["first", "second"])
        XCTAssertEqual(payloads.compactMap { $0["userPasswordConfirm"] as? String }, ["PASSWORD_SECRET", "PASSWORD_SECRET"])
        assertNoMetadataOrErrorDetails(logs.lines)
    }

    func testPreservesProducerAndWriterFailures() async throws {
        let error = RPCError(code: .cancelled, message: "ERROR_SECRET")
        for producerFails in [false, true] {
            let logs = LogCapture()
            let interceptor = GRPCLoggingInterceptor(output: { logs.append($0) })
            let request = StreamingClientRequest<String> { writer in
                if producerFails { throw error }
                try await writer.write("PASSWORD_SECRET")
            }
            do {
                let _: Response = try await interceptor.intercept(request: request, context: context) { forwarded, _ in
                    try await forwarded.producer(RPCWriter(wrapping: RecordingWriter<String>(error: error)))
                    return Response(error: RPCError(code: .unknown, message: "Unexpected success"))
                }
                XCTFail("The original producer or writer error must reach the caller")
            } catch let actual as RPCError {
                XCTAssertEqual(actual, error)
            }
            XCTAssertTrue(logs.lines.last?.contains("status=cancelled") == true)
            assertLogPair(logs.lines)
            assertNoMetadataOrErrorDetails(logs.lines)
        }
    }

    func testLogsSuccessOnlyAfterConsumptionAndPreservesResponse() async throws {
        let logs = LogCapture()
        let interceptor = GRPCLoggingInterceptor(output: { logs.append($0) })
        let parts: [Part] = [.message("RESPONSE_SECRET"), .trailingMetadata(["token": "TRAILER_SECRET"])]
        let response: Response = try await interceptor.intercept(request: request(), context: context) { request, _ in
            XCTAssertEqual(request.metadata, ["authorization": "REQUEST_SECRET"])
            return self.response(parts: parts, metadata: ["token": "HEADER_SECRET"])
        }

        XCTAssertEqual(logs.lines.count, 1, "Receiving headers must not log a successful RPC")
        XCTAssertTrue(logs.lines[0].contains("event=start"))
        XCTAssertEqual(response.metadata, ["token": "HEADER_SECRET"])
        var received: [Part] = []
        var iterator = response.bodyParts.makeAsyncIterator()
        while let part = try await iterator.next() { received.append(part) }
        _ = try await iterator.next()

        XCTAssertEqual(received, parts)
        XCTAssertEqual(logs.lines.count, 3, "Expected start, response and a single result")
        XCTAssertTrue(logs.lines.last?.contains("status=ok") == true)
        XCTAssertTrue(logs.lines.contains { $0.contains("event=response ") && $0.contains("<payload_unavailable>") })
        assertLogPair(logs.lines)
        assertNoMetadataOrErrorDetails(logs.lines)
    }

    func testRejectedAndThrownErrorsAreLoggedAndPreserved() async throws {
        let error = RPCError(code: .unauthenticated, message: "ERROR_SECRET", metadata: ["token": "TRAILER_SECRET"])
        for throwsDirectly in [false, true] {
            let logs = LogCapture()
            let interceptor = GRPCLoggingInterceptor(output: { logs.append($0) })
            do {
                let response: Response = try await interceptor.intercept(request: request(), context: context) { _, _ in
                    if throwsDirectly { throw error }
                    return Response(error: error)
                }
                for try await _ in response.messages {}
                XCTFail("The original error must reach the caller")
            } catch let actual as RPCError {
                XCTAssertEqual(actual, error)
            }
            XCTAssertEqual(logs.lines.count, 2)
            XCTAssertTrue(logs.lines.last?.contains("status=unauthenticated") == true)
            assertLogPair(logs.lines)
            assertNoMetadataOrErrorDetails(logs.lines)
        }
    }

    func testLateStreamErrorsAndCancellationNeverLogSuccess() async throws {
        let rpcError = RPCError(code: .unavailable, message: "ERROR_SECRET")
        for afterTrailers in [false, true] {
            for cancelled in [false, true] {
                let logs = LogCapture()
                let interceptor = GRPCLoggingInterceptor(output: { logs.append($0) })
                let error: any Error = cancelled ? CancellationError() : rpcError
                var parts: [Part] = [.message("RESPONSE_SECRET")]
                if afterTrailers { parts.append(.trailingMetadata([:])) }
                let original = response(parts: parts, error: error)
                let response: Response = try await interceptor.intercept(request: request(), context: context) { _, _ in original }
                XCTAssertEqual(logs.lines.count, 1)
                do {
                    for try await _ in response.bodyParts {}
                    XCTFail("A stream failure must reach the caller")
                } catch {
                    if cancelled {
                        XCTAssertTrue(error is CancellationError)
                    } else {
                        XCTAssertEqual(error as? RPCError, rpcError)
                    }
                }
                XCTAssertEqual(logs.lines.count, 3)
                XCTAssertTrue(logs.lines.last?.contains(cancelled ? "status=cancelled" : "status=unavailable") == true)
                XCTAssertFalse(logs.lines.contains { $0.contains("status=ok") })
                assertNoMetadataOrErrorDetails(logs.lines)
            }
        }
    }

    func testStreamWithoutTrailersDoesNotReportSuccess() async throws {
        let logs = LogCapture()
        let interceptor = GRPCLoggingInterceptor(output: { logs.append($0) })
        let original = response(parts: [.message("RESPONSE_SECRET")])
        let response: Response = try await interceptor.intercept(request: request(), context: context) { _, _ in original }
        for try await _ in response.bodyParts {}
        XCTAssertEqual(logs.lines.count, 3)
        XCTAssertTrue(logs.lines.last?.contains("status=incomplete") == true)
    }

    private func request() -> StreamingClientRequest<String> {
        StreamingClientRequest(metadata: ["authorization": "REQUEST_SECRET"]) { writer in
            try await writer.write("PASSWORD_SECRET")
        }
    }

    private func response(parts: [Part], metadata: Metadata = [:], error: (any Error)? = nil) -> Response {
        let stream = AsyncThrowingStream<Part, any Error> { continuation in
            for part in parts { continuation.yield(part) }
            continuation.finish(throwing: error)
        }
        return Response(metadata: metadata, bodyParts: RPCAsyncSequence(wrapping: stream))
    }

    private func assertLogPair(_ lines: [String], file: StaticString = #filePath, line: UInt = #line) {
        let lifecycle = lines.filter { $0.contains("event=start ") || $0.contains("event=end ") }
        guard lifecycle.count == 2 else { return XCTFail("Expected a start and a result", file: file, line: line) }
        for entry in lines {
            XCTAssertTrue(entry.contains("method=auth.AuthService/SignIn"), file: file, line: line)
        }
        let ids = lines.map { $0.split(separator: " ").first { $0.hasPrefix("id=") } }
        XCTAssertNotNil(ids[0], file: file, line: line)
        for id in ids { XCTAssertEqual(id, ids[0], file: file, line: line) }
        let duration = lifecycle[1].split(separator: " ").first { $0.hasPrefix("duration_ms=") }
        let milliseconds = duration.flatMap { Double($0.dropFirst("duration_ms=".count)) }
        XCTAssertNotNil(milliseconds, file: file, line: line)
        XCTAssertGreaterThanOrEqual(milliseconds ?? -1, 0, file: file, line: line)
    }

    private func payload(in lines: [String], event: String) throws -> [String: Any] {
        let entry = try XCTUnwrap(lines.first { $0.contains("event=\(event) ") })
        let bodyStart = try XCTUnwrap(entry.firstIndex(of: "\n"))
        let data = Data(entry[entry.index(after: bodyStart)...].utf8)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func assertNoMetadataOrErrorDetails(_ lines: [String], file: StaticString = #filePath, line: UInt = #line) {
        for marker in ["REQUEST_SECRET", "HEADER_SECRET", "TRAILER_SECRET", "ERROR_SECRET"] {
            XCTAssertFalse(lines.joined().contains(marker), file: file, line: line)
        }
    }
}

private final class RecordingWriter<Element: Sendable>: RPCWriterProtocol {
    private let storage = Mutex<[Element]>([])
    private let error: (any Error)?
    var messages: [Element] { storage.withLock { $0 } }

    init(error: (any Error)? = nil) { self.error = error }

    func write(_ element: Element) async throws {
        if let error { throw error }
        storage.withLock { $0.append(element) }
    }

    func write(contentsOf elements: some Sequence<Element>) async throws {
        for element in elements { try await write(element) }
    }
}

private final class LogCapture: Sendable {
    private let storage = Mutex<[String]>([])
    var lines: [String] { storage.withLock { $0 } }
    func append(_ line: String) { storage.withLock { $0.append(line) } }
}
#endif
