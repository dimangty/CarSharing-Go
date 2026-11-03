import GRPCCore
import SwiftProtobuf

struct GRPCAuthRepository: AuthRepository {
    let client: GRPCClient

    func signIn(login: String, password: String) async throws -> AuthSession {
        let request = Auth_SignInRequest.with {
            $0.userName = login
            $0.userPassword = password
            $0.userIdentifyString = "carsharing-ios-local"
        }
        let response: Auth_SignInResponse = try await client.withAuthClient {
            try await $0.signIn(request, options: GRPCClient.callOptions)
        }
        return try Self.session(success: response.success, access: response.accessToken, refresh: response.refreshToken)
    }

    func signUp(login: String, password: String, confirmation: String) async throws -> AuthSession {
        let request = Auth_SignUpRequest.with {
            $0.userName = login
            $0.userPassword = password
            $0.userPasswordConfirm = confirmation
        }
        let response: Auth_SignUpResponse = try await client.withAuthClient {
            try await $0.signUp(request, options: GRPCClient.callOptions)
        }
        return try Self.session(success: response.success, access: response.accessToken, refresh: response.refreshToken)
    }

    nonisolated static func session(success: Bool, access: String, refresh: String) throws -> AuthSession {
        guard success, !access.isEmpty, !refresh.isEmpty else { throw AuthError.invalidResponse }
        return AuthSession(accessToken: access, refreshToken: refresh)
    }
}
