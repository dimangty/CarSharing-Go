import XCTest
import GRPCCore
import Security
#if canImport(Client)
@testable import Client
private typealias AppGRPCClient = Client.GRPCClient
#else
@testable import ClientAuth
private typealias AppGRPCClient = ClientAuth.GRPCClient
#endif

@MainActor
final class GRPCIntegrationTests: XCTestCase {
    private func realClient() throws -> AppGRPCClient {
        guard ProcessInfo.processInfo.environment["RUN_GRPC_INTEGRATION"] == "1" else {
            throw XCTSkip("Start the Go mock gateway and set RUN_GRPC_INTEGRATION=1 (or use Client-Integration scheme)")
        }
        return AppGRPCClient(configuration: try GRPCConfiguration.application())
    }

    func testRealSignUpNavigatesToSuccessAndPersistsTokens() async throws {
        let repository = GRPCAuthRepository(client: try realClient())
        let storage = IntegrationStorage()
        defer { storage.cleanup() }
        let flow = AuthFlow()
        flow.showRegistration()
        let model = RegistrationViewModel(repository: repository, storage: storage, onSuccess: { flow.authenticated() })
        model.login = "new_user"
        model.password = "123456"
        model.confirmation = "123456"
        await model.submit()
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(flow.screen, .success)
        XCTAssertFalse(model.isLoading)
        try storage.assertMockTokens()
    }

    func testRealSignInWithoutRegistrationNavigatesToSuccess() async throws {
        let repository = GRPCAuthRepository(client: try realClient())
        let storage = IntegrationStorage()
        defer { storage.cleanup() }
        let flow = AuthFlow()
        let model = LoginViewModel(repository: repository, storage: storage, onSuccess: { flow.authenticated() })
        model.login = "unregistered_user"
        model.password = "any_nonempty_password"
        await model.submit()
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(flow.screen, .success)
        XCTAssertFalse(model.isLoading)
        try storage.assertMockTokens()
    }

    func testRealTransportDeliversInvalidArgument() async throws {
        let client = try realClient()
        do {
            let _: Auth_SignUpResponse = try await client.withAuthClient {
                var request = Auth_SignUpRequest()
                request.userName = "invalid_confirmation_user"
                request.userPassword = "123456"
                request.userPasswordConfirm = "different"
                return try await $0.signUp(request, options: AppGRPCClient.callOptions)
            }
            XCTFail("Mismatched confirmation must fail on the server")
        } catch let error as RPCError {
            XCTAssertEqual(error.code, .invalidArgument)
        }
    }
}

@MainActor
private final class IntegrationStorage: SessionStorage {
    private let keychain = KeychainSessionStorage(service: "carsharing.integration.\(UUID().uuidString)")
    private var saved: AuthSession?

    func save(_ session: AuthSession) throws {
        #if os(iOS)
        try keychain.save(session)
        #endif
        saved = session
    }

    func assertMockTokens() throws {
        var session = saved
        #if os(iOS)
        var data: CFTypeRef?
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychain.service,
            kSecAttrAccount as String: "mock-session",
            kSecReturnData as String: true,
        ]
        XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &data), errSecSuccess)
        session = try JSONDecoder().decode(AuthSession.self, from: XCTUnwrap(data as? Data))
        #endif
        XCTAssertEqual(session?.accessToken, "mock_access_token")
        XCTAssertEqual(session?.refreshToken, "mock_refresh_token")
    }

    func cleanup() {
        #if os(iOS)
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychain.service] as CFDictionary)
        #endif
    }
}
