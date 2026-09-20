import Foundation
import Security

@MainActor
protocol KeychainBackend {
    func containsAPIKey() throws -> Bool
    func getAPIKey() throws -> String?
    func saveAPIKey(_ value: String) throws
    func deleteAPIKey() throws
}

@MainActor
final class KeychainService {
    let service: String
    let account: String
    private let backend: any KeychainBackend
    private var cachedAPIKey: String?

    init(service: String = "com.ovo.translator", account: String = "deepseek-api-key",
         backend: (any KeychainBackend)? = nil) {
        self.service = service
        self.account = account
        self.backend = backend ?? SystemKeychainBackend(service: service, account: account)
    }

    /// Checks metadata only. Opening settings must never trigger a secret-access prompt.
    func containsAPIKey() throws -> Bool {
        let isPresent = try backend.containsAPIKey()
        // A confirmed external deletion must agree with the configuration status.
        // Failed checks still preserve a previously authorized session value.
        if !isPresent { cachedAPIKey = nil }
        return isPresent
    }

    func getAPIKey() throws -> String? {
        if let cachedAPIKey { return cachedAPIKey }
        let value = try backend.getAPIKey()
        if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cachedAPIKey = value
        }
        return value
    }

    func saveAPIKey(_ value: String) throws {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw KeychainError.emptyKey }
        try backend.saveAPIKey(key)
        cachedAPIKey = key
    }

    func deleteAPIKey() throws {
        try backend.deleteAPIKey()
        cachedAPIKey = nil
    }
}

/// Uses the existing login-keychain item and leaves its access control unchanged.
@MainActor
private final class SystemKeychainBackend: KeychainBackend {
    private let service: String
    private let account: String

    init(service: String, account: String) {
        self.service = service
        self.account = account
    }

    func containsAPIKey() throws -> Bool {
        // SecItem's authentication-UI option does not silence all legacy login-keychain
        // prompts. Scope the legacy interaction flag to this synchronous MainActor call.
        var wasInteractionAllowed: DarwinBoolean = false
        let readStatus = SecKeychainGetUserInteractionAllowed(&wasInteractionAllowed)
        guard readStatus == errSecSuccess else { throw KeychainError.operationFailed(readStatus) }
        let disableStatus = SecKeychainSetUserInteractionAllowed(false)
        guard disableStatus == errSecSuccess else { throw KeychainError.operationFailed(disableStatus) }
        defer { SecKeychainSetUserInteractionAllowed(wasInteractionAllowed.boolValue) }

        var query = baseQuery
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw KeychainError.operationFailed(status) }
        return true
    }

    func getAPIKey() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.operationFailed(status) }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return value
    }

    func saveAPIKey(_ value: String) throws {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw KeychainError.emptyKey }
        let data = Data(key.utf8)
        let status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = baseQuery
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = account == "deepseek-api-key" ? "OvO · DeepSeek API Key" : "OvO · 自定义 API Key"
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.operationFailed(addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError.operationFailed(status)
        }
    }

    func deleteAPIKey() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.operationFailed(status)
        }
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}

enum KeychainError: LocalizedError {
    case operationFailed(OSStatus)
    case invalidData
    case emptyKey

    var errorDescription: String? {
        switch self {
        case .operationFailed(let status):
            if status == errSecUserCanceled { return "钥匙串授权已取消，请重试并允许 OvO 访问。" }
            if status == errSecInteractionNotAllowed { return "钥匙串当前已锁定，请解锁后重试。" }
            return "无法访问系统钥匙串（错误 \(status)），请检查钥匙串访问权限。"
        case .invalidData: return "钥匙串中的 API Key 无法读取，请重新保存。"
        case .emptyKey: return "请输入 API Key。"
        }
    }
}
