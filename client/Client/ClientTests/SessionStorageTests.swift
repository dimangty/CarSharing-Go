import XCTest
import Security
#if canImport(Client)
@testable import Client
#else
@testable import ClientAuth
#endif

#if os(iOS)
@MainActor
final class SessionStorageTests: XCTestCase {
    func testPersistsAndReplacesSessionWithEmptyTokens() throws {
        let service = "carsharing.session-tests.\(UUID().uuidString)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "mock-session",
        ]
        defer { SecItemDelete(query as CFDictionary) }
        let storage = KeychainSessionStorage(service: service)
        try storage.save(AuthSession(accessToken: "old-access", refreshToken: "old-refresh", userIdentifyString: "old-pair"))
        let session = AuthSession(accessToken: "", refreshToken: "", userIdentifyString: "new-pair")
        try storage.save(session)

        var result: CFTypeRef?
        let readQuery = query.merging([kSecReturnData as String: true]) { _, new in new }
        XCTAssertEqual(SecItemCopyMatching(readQuery as CFDictionary, &result), errSecSuccess)
        let decoded = try JSONDecoder().decode(AuthSession.self, from: XCTUnwrap(result as? Data))
        XCTAssertEqual(decoded, session)
    }
}
#endif
