import Foundation

struct AuthSession: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
}

@MainActor
protocol AuthRepository {
    func signIn(login: String, password: String) async throws -> AuthSession
    func signUp(login: String, password: String, confirmation: String) async throws -> AuthSession
}
