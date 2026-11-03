import Foundation
import Security

@MainActor
protocol SessionStorage {
    func save(_ session: AuthSession) throws
}

// Only local Debug builds persist these mock tokens. Passwords never enter storage.
@MainActor
struct KeychainSessionStorage: SessionStorage {
    let service: String

    init(service: String = "carsharing.local-auth") {
        self.service = service
    }

    func save(_ session: AuthSession) throws {
        #if DEBUG
        let data = try JSONEncoder().encode(session)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "mock-session",
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let item = query.merging(attributes) { _, new in new }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw AuthError.storage }
        } else if status != errSecSuccess {
            throw AuthError.storage
        }
        #else
        throw AuthError.storage
        #endif
    }
}
