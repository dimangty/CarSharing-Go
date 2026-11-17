import Foundation

struct AuthSession: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let userIdentifyString: String
}

@MainActor
protocol AuthRepository {
    func signIn(login: String, password: String) async throws -> AuthSession
    func signUp(login: String, password: String) async throws -> AuthSession
}
