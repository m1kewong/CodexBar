import Foundation
import Security

enum ProviderAPITokenStore {
    private static let service = "com.steipete.codexbar.ios"

    private static let accounts: [String: String] = [
        "claude": "claude-session-credential",
        "cursor": "cursor-cookie-header",
        "opencode": "opencode-cookie-header",
        "augment": "augment-cookie-header",
        "factory": "factory-cookie-header",
        "amp": "amp-cookie-header",
        "gemini": "gemini-access-token",
        "vertexai": "vertexai-credential",
        "zai": "zai-api-token",
        "minimax": "minimax-api-token",
        "synthetic": "synthetic-api-token",
        "kimik2": "kimik2-api-token",
        "kimi": "kimi-auth-token",
    ]

    static func load(_ providerID: String) -> String? {
        guard let account = Self.accounts[providerID] else { return nil }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    static func save(_ token: String, for providerID: String) {
        guard let account = Self.accounts[providerID] else { return }
        let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            Self.clear(providerID)
            return
        }

        let data = Data(cleaned.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]

        let update: [String: Any] = [
            kSecValueData as String: data,
        ]

        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess {
            return
        }

        var insert = query
        insert[kSecValueData as String] = data
        SecItemAdd(insert as CFDictionary, nil)
    }

    static func clear(_ providerID: String) {
        guard let account = Self.accounts[providerID] else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
