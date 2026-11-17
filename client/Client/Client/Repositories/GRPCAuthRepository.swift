import GRPCCore
import SwiftProtobuf

struct GRPCAuthRepository: AuthRepository {
    let client: any AuthRPCClient
    let identityStorage: any UserDeviceIdentityStorage

    init(client: any AuthRPCClient, identityStorage: any UserDeviceIdentityStorage = KeychainUserDeviceIdentityStorage()) {
        self.client = client
        self.identityStorage = identityStorage
    }

    func signIn(login: String, password: String) async throws -> AuthSession {
        let identity = try identityStorage.identifyString(for: login)
        let request = Auth_SignInRequest.with {
            $0.userName = login
            $0.userPassword = password
            $0.userIdentifyString = identity
        }
        let response = try await client.signIn(request)
        return try Self.session(success: response.success, access: response.accessToken, refresh: response.refreshToken, identity: identity)
    }

    func signUp(login: String, password: String) async throws -> AuthSession {
        let identity = try identityStorage.identifyString(for: login)
        let request = Auth_SignUpRequest.with {
            $0.userName = login
            $0.userPassword = password
            $0.userIdentifyString = identity
        }
        let response = try await client.signUp(request)
        return try Self.session(success: response.success, access: response.accessToken, refresh: response.refreshToken, identity: identity)
    }

    nonisolated static func session(success: Bool, access: String, refresh: String, identity: String) throws -> AuthSession {
        guard success else { throw AuthError.invalidResponse }
        return AuthSession(accessToken: access, refreshToken: refresh, userIdentifyString: identity)
    }
}
