import XCTest
import GRPCCore
#if canImport(Client)
@testable import Client
#else
@testable import ClientAuth
#endif

@MainActor
final class AuthRequestTests: XCTestCase {
    func testSignUpAndSignInSendIdentityForTheRequestedAccount() async throws {
        let client = RecordingAuthRPCClient()
        let identities = TestIdentityStorage()
        let repository = GRPCAuthRepository(client: client, identityStorage: identities)
        _ = try await repository.signUp(login: "Alice", password: " password ")
        _ = try await repository.signIn(login: "Alice", password: "changed-password")
        _ = try await repository.signIn(login: "Bob", password: "other-password")
        let signUps = await client.signUps
        let signIns = await client.signIns
        XCTAssertEqual(identities.logins, ["Alice", "Alice", "Bob"])
        XCTAssertEqual(signUps.map(\.userName), ["Alice"])
        XCTAssertEqual(signUps.map(\.userPassword), [" password "])
        XCTAssertEqual(signUps.map(\.userIdentifyString), ["alice-device-id"])
        XCTAssertEqual(signIns.map(\.userName), ["Alice", "Bob"])
        XCTAssertEqual(signIns.map(\.userPassword), ["changed-password", "other-password"])
        XCTAssertEqual(signIns.map(\.userIdentifyString), ["alice-device-id", "bob-device-id"])
    }

    func testBothOperationsAcceptSuccessWithAnyTokenCombination() async throws {
        for (access, refresh) in [("", ""), ("a", ""), ("", "r"), ("a", "r")] {
            let client = RecordingAuthRPCClient(access: access, refresh: refresh)
            let repository = GRPCAuthRepository(client: client, identityStorage: TestIdentityStorage())
            let signIn = try await repository.signIn(login: "Alice", password: "password")
            let signUp = try await repository.signUp(login: "Alice", password: "password")
            for session in [signIn, signUp] {
                XCTAssertEqual(session.accessToken, access)
                XCTAssertEqual(session.refreshToken, refresh)
                let data = try JSONEncoder().encode(session)
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                XCTAssertEqual(json["userIdentifyString"] as? String, "alice-device-id")
            }
        }
    }

    func testIdentityStorageFailurePreventsBothRPCs() async {
        let client = RecordingAuthRPCClient()
        let identities = TestIdentityStorage()
        identities.shouldFail = true
        let repository = GRPCAuthRepository(client: client, identityStorage: identities)
        for signUp in [false, true] {
            do {
                _ = try await signUp
                    ? repository.signUp(login: "Alice", password: "password")
                    : repository.signIn(login: "Alice", password: "password")
                XCTFail("Identity must be persisted before sending the request")
            } catch {
                XCTAssertEqual(error as? AuthError, .storage)
            }
        }
        let signIns = await client.signIns
        let signUps = await client.signUps
        XCTAssertTrue(signIns.isEmpty)
        XCTAssertTrue(signUps.isEmpty)
    }

    func testBothOperationsPropagateServerFailure() async {
        for rpcError in [nil, RPCError(code: .unavailable, message: "offline")] {
            let client = RecordingAuthRPCClient(success: false, access: "a", refresh: "r", error: rpcError)
            let repository = GRPCAuthRepository(client: client, identityStorage: TestIdentityStorage())
            for signUp in [false, true] {
                do {
                    _ = try await signUp
                        ? repository.signUp(login: "Alice", password: "password")
                        : repository.signIn(login: "Alice", password: "password")
                    XCTFail("A failed response must not produce a session")
                } catch {
                    if let rpcError { XCTAssertEqual(error as? RPCError, rpcError) }
                    else { XCTAssertEqual(error as? AuthError, .invalidResponse) }
                }
            }
        }
    }
}

@MainActor
private final class TestIdentityStorage: UserDeviceIdentityStorage {
    var logins: [String] = []
    var shouldFail = false

    func identifyString(for login: String) throws -> String {
        logins.append(login)
        if shouldFail { throw AuthError.storage }
        switch login {
        case "Alice": return "alice-device-id"
        case "Bob": return "bob-device-id"
        default: throw AuthError.storage
        }
    }
}

private actor RecordingAuthRPCClient: AuthRPCClient {
    private(set) var signIns: [Auth_SignInRequest] = []
    private(set) var signUps: [Auth_SignUpRequest] = []
    private let signInResponse: Auth_SignInResponse
    private let signUpResponse: Auth_SignUpResponse
    private let error: RPCError?

    init(success: Bool = true, access: String = "", refresh: String = "", error: RPCError? = nil) {
        var signIn = Auth_SignInResponse()
        signIn.success = success
        signIn.accessToken = access
        signIn.refreshToken = refresh
        signInResponse = signIn
        var signUp = Auth_SignUpResponse()
        signUp.success = success
        signUp.accessToken = access
        signUp.refreshToken = refresh
        signUpResponse = signUp
        self.error = error
    }

    func signIn(_ request: Auth_SignInRequest) async throws -> Auth_SignInResponse {
        signIns.append(request)
        if let error { throw error }
        return signInResponse
    }

    func signUp(_ request: Auth_SignUpRequest) async throws -> Auth_SignUpResponse {
        signUps.append(request)
        if let error { throw error }
        return signUpResponse
    }
}
