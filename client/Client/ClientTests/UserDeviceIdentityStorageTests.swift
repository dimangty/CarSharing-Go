import XCTest
import Security
#if canImport(Client)
@testable import Client
#else
@testable import ClientAuth
#endif

#if os(iOS)
@MainActor
final class UserDeviceIdentityStorageTests: XCTestCase {
    func testIdentitySurvivesNewStorageInstanceAndAccountSwitching() throws {
        let service = "carsharing.identity-tests.\(UUID().uuidString)"
        defer { deleteItems(service: service) }
        let storage = KeychainUserDeviceIdentityStorage(service: service)
        let alice = try storage.identifyString(for: "Alice")
        let bob = try storage.identifyString(for: "Bob")
        XCTAssertNotNil(UUID(uuidString: alice))
        XCTAssertNotEqual(alice, bob)
        XCTAssertNotEqual(alice, try storage.identifyString(for: "alice"))
        XCTAssertEqual(try storage.identifyString(for: "Alice"), alice)
        XCTAssertEqual(try KeychainUserDeviceIdentityStorage(service: service).identifyString(for: "Alice"), alice)
    }

    func testSeparateDeviceStoresHaveDifferentIdentitiesAndNeverSynchronize() throws {
        let firstService = "carsharing.identity-tests.\(UUID().uuidString)"
        let secondService = "carsharing.identity-tests.\(UUID().uuidString)"
        defer {
            deleteItems(service: firstService)
            deleteItems(service: secondService)
        }
        let first = try KeychainUserDeviceIdentityStorage(service: firstService).identifyString(for: "Alice")
        let second = try KeychainUserDeviceIdentityStorage(service: secondService).identifyString(for: "Alice")
        XCTAssertNotEqual(first, second)

        var result: CFTypeRef?
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: firstService,
            kSecAttrAccount as String: "Alice",
            kSecReturnAttributes as String: true,
        ]
        XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &result), errSecSuccess)
        let attributes = try XCTUnwrap(result as? [String: Any])
        XCTAssertEqual(attributes[kSecAttrAccessible as String] as? String, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        XCTAssertEqual(attributes[kSecAttrSynchronizable as String] as? Bool, false)
    }

    func testCorruptedIdentityIsNotSilentlyReplaced() throws {
        let service = "carsharing.identity-tests.\(UUID().uuidString)"
        defer { deleteItems(service: service) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "Alice",
        ]
        for data in [Data(), Data([0xff]), Data("not-a-uuid".utf8)] {
            deleteItems(service: service)
            let item = query.merging([kSecValueData as String: data]) { _, new in new }
            XCTAssertEqual(SecItemAdd(item as CFDictionary, nil), errSecSuccess)
            XCTAssertThrowsError(try KeychainUserDeviceIdentityStorage(service: service).identifyString(for: "Alice")) {
                XCTAssertEqual($0 as? AuthError, .storage)
            }
            var result: CFTypeRef?
            let readQuery = query.merging([kSecReturnData as String: true]) { _, new in new }
            XCTAssertEqual(SecItemCopyMatching(readQuery as CFDictionary, &result), errSecSuccess)
            XCTAssertEqual(result as? Data, data)
        }
    }

    private func deleteItems(service: String) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ] as CFDictionary)
    }
}
#endif
