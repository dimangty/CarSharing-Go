import XCTest
import GRPCCore
#if canImport(Client)
@testable import Client
#else
@testable import ClientAuth
#endif

final class RepositoryTests: XCTestCase {
    func testSuccessDoesNotRequireTokens() throws {
        for (access, refresh) in [("", ""), ("", "r"), ("a", ""), ("a", "r")] {
            XCTAssertEqual(
                try GRPCAuthRepository.session(success: true, access: access, refresh: refresh, identity: "pair-id"),
                AuthSession(accessToken: access, refreshToken: refresh, userIdentifyString: "pair-id")
            )
        }
    }

    func testRejectsUnsuccessfulResponsesRegardlessOfTokens() {
        for (access, refresh) in [("", ""), ("a", "r")] {
            XCTAssertThrowsError(try GRPCAuthRepository.session(success: false, access: access, refresh: refresh, identity: "pair-id"))
        }
    }

    func testSignUpIdentifyStringUsesFieldThreeAndCurrentJSONName() throws {
        let request = try Auth_SignUpRequest(jsonString: #"{"userName":"n","userPassword":"p","userIdentifyString":"i"}"#)
        // Hand-encoded fixture from auth.proto: three length-delimited strings, fields 1, 2, 3.
        XCTAssertEqual(try request.serializedData(), Data([0x0a, 1, 0x6e, 0x12, 1, 0x70, 0x1a, 1, 0x69]))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: request.jsonUTF8Data()) as? [String: Any])
        XCTAssertEqual(json["userIdentifyString"] as? String, "i")
        XCTAssertNil(json["userPasswordConfirm"])
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
