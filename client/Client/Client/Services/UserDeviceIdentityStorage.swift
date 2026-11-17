import Foundation
import Security

@MainActor
protocol UserDeviceIdentityStorage {
    func identifyString(for login: String) throws -> String
}

@MainActor
struct KeychainUserDeviceIdentityStorage: UserDeviceIdentityStorage {
    let service: String

    init(service: String = "carsharing.auth-pair-id.v1") {
        self.service = service
    }

    func identifyString(for login: String) throws -> String {
        // Use the same case-sensitive login sent to the server. Each account has
        // its own ID; ThisDeviceOnly and disabled sync keep it local to this device.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: login,
            kSecAttrSynchronizable as String: false,
        ]
        if let existing = try read(query) { return existing }

        let identity = UUID().uuidString.lowercased()
        let attributes: [String: Any] = [
            kSecValueData as String: Data(identity.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let item = query.merging(attributes) { _, new in new }
        switch SecItemAdd(item as CFDictionary, nil) {
        case errSecSuccess:
            return identity
        case errSecDuplicateItem:
            // Another writer may have created the pair while we were reading.
            guard let existing = try read(query) else { throw AuthError.storage }
            return existing
        default:
            throw AuthError.storage
        }
    }

    private func read(_ query: [String: Any]) throws -> String? {
        let readQuery = query.merging([
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]) { _, new in new }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(readQuery as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let identity = String(data: data, encoding: .utf8),
              UUID(uuidString: identity) != nil else { throw AuthError.storage }
        return identity
    }
}
