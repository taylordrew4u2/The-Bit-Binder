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
                do {
                    try save(trimmed)
                } catch {
                    DataOperationLogger.shared.logError(
                        error,
                        operation: "OpenAIKeychainStore.save",
                        context: "Could not persist OpenAI API key"
                    )
                }
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

        do {
            try save(legacyValue)
        } catch {
            DataOperationLogger.shared.logError(
                error,
                operation: "OpenAIKeychainStore.migrateLegacyValueIfNeeded",
                context: "Could not migrate legacy OpenAI API key"
            )
            return ""
        }
        clearLegacyDefaultsValue()
        return legacyValue
    }

    private func save(_ value: String) throws {
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
            let addStatus = SecItemAdd(newItem as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unhandledStatus(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.unhandledStatus(updateStatus)
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

    private enum KeychainError: LocalizedError {
        case unhandledStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .unhandledStatus(let status):
                return "Keychain operation failed with status \(status)."
            }
        }
    }
}
