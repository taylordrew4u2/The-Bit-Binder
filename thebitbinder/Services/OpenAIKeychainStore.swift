import Foundation
import Security

struct OpenAIKeychainStore {
    static let shared = OpenAIKeychainStore()

    private let service = "TheBitBinder.OpenAI"
    private let account = "apiKey"
    private let legacyDefaultsKey = "openAIAPIKey"

    private init() {}

    var apiKey: String {
        get {
            guard let data = copyMatchingData(),
                  let value = String(data: data, encoding: .utf8) else {
                return ""
            }
            return value
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                delete()
            } else {
                save(trimmed)
            }
        }
    }

    @discardableResult
    func migrateLegacyValueIfNeeded() -> String {
        let existingKey = apiKey
        if !existingKey.isEmpty {
            clearLegacyDefaultsValue()
            return existingKey
        }

        let legacyValue = UserDefaults.standard.string(forKey: legacyDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !legacyValue.isEmpty else {
            clearLegacyDefaultsValue()
            return ""
        }

        save(legacyValue)
        clearLegacyDefaultsValue()
        return legacyValue
    }

    private func save(_ value: String) {
        let data = Data(value.utf8)
        let query = baseQuery()
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }

    private func delete() {
        SecItemDelete(baseQuery() as CFDictionary)
        clearLegacyDefaultsValue()
    }

    private func copyMatchingData() -> Data? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func clearLegacyDefaultsValue() {
        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
    }
}
