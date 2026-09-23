import Foundation
import Security

/// Keeps the account token so the account comes back after a reinstall.
/// Order: Keychain (iCloud Keychain sync) → iCloud key-value store → StoreKit appAccountToken → new guest.
enum AccountStore {
    private static let service = "com.faxlane.account"
    private static let key = "accountToken"

    static func loadToken() -> UUID? {
        if let fromKeychain = readKeychain() { return fromKeychain }
        if let raw = NSUbiquitousKeyValueStore.default.string(forKey: key), let id = UUID(uuidString: raw) {
            saveToken(id)
            return id
        }
        return nil
    }

    static func saveToken(_ token: UUID) {
        let data = Data(token.uuidString.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
        NSUbiquitousKeyValueStore.default.set(token.uuidString, forKey: key)
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    static func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        SecItemDelete(query as CFDictionary)
        NSUbiquitousKeyValueStore.default.removeObject(forKey: key)
    }

    private static func readKeychain() -> UUID? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let raw = String(data: data, encoding: .utf8) else { return nil }
        return UUID(uuidString: raw)
    }
}
