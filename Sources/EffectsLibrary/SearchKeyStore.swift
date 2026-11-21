// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Foundation
import Security

/// The user's own search-service key, kept in the macOS Keychain (never in files, defaults, logs or source).
enum SearchKeyStore {
    private static let service = "dev.gordas.GDCEffectsLibrary.search-key"
    private static let account = "brave-search"
    private static func query() -> [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] }

    static func read() -> String? {
        var q = query(); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    @discardableResult static func save(_ key: String) -> Bool {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty, let d = k.data(using: .utf8) else { return false }
        SecItemDelete(query() as CFDictionary)
        var q = query(); q[kSecValueData as String] = d; q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }
    @discardableResult static func remove() -> Bool { let s = SecItemDelete(query() as CFDictionary); return s == errSecSuccess || s == errSecItemNotFound }
}
