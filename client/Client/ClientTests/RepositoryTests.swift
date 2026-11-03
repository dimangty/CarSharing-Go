import XCTest
import GRPCCore
#if canImport(Client)
@testable import Client
#else
@testable import ClientAuth
#endif

final class RepositoryTests: XCTestCase {
    func testRejectsFailureAndIncompleteResponses() {
        for (success, access, refresh) in [(false, "a", "r"), (true, "", "r"), (true, "a", "")] {
            XCTAssertThrowsError(try GRPCAuthRepository.session(success: success, access: access, refresh: refresh))
        }
        XCTAssertEqual(try GRPCAuthRepository.session(success: true, access: "a", refresh: "r"), AuthSession(accessToken: "a", refreshToken: "r"))
    }

    func testEndpointDefaultsAndOverrides() throws {
        let local = try GRPCConfiguration(values: [:], isDebug: true)
        XCTAssertEqual(local.host, "localhost")
        XCTAssertEqual(local.port, 50051)
        XCTAssertFalse(local.useTLS)
        let device = try GRPCConfiguration(values: ["GRPC_HOST": "192.168.1.10", "GRPC_PORT": "50052"], isDebug: true)
        XCTAssertEqual(device.host, "192.168.1.10")
        XCTAssertEqual(device.port, 50052)
    }

    func testReleaseRequiresHostAndTLS() throws {
        XCTAssertThrowsError(try GRPCConfiguration(values: [:], isDebug: false))
        XCTAssertThrowsError(try GRPCConfiguration(values: ["GRPC_HOST": "example.com", "GRPC_TLS": "false"], isDebug: false))
        let release = try GRPCConfiguration(values: ["GRPC_HOST": "example.com"], isDebug: false)
        XCTAssertTrue(release.useTLS)
        for values in [["GRPC_PORT": "0"], ["GRPC_PORT": "65536"], ["GRPC_PORT": "abc"], ["GRPC_TLS": "invalid"], ["GRPC_HOST": " \n"]] {
            XCTAssertThrowsError(try GRPCConfiguration(values: values, isDebug: true))
        }
    }

    func testGRPCErrorsHaveActionableMessages() {
        for code: RPCError.Code in [.invalidArgument, .unauthenticated, .unavailable, .deadlineExceeded, .resourceExhausted, .unimplemented, .internalError] {
            let message = AuthError.message(for: RPCError(code: code, message: "sensitive server detail"))
            XCTAssertFalse(message.isEmpty)
            XCTAssertFalse(message.contains("sensitive"))
        }
    }
}
