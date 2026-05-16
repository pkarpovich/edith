import Foundation
import Security

enum KeychainError: Error, Equatable, LocalizedError {
    case encodingFailed
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Could not encode the key as UTF-8 data."
        case .unexpectedStatus(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return "Keychain error: \(message)"
        }
    }
}

protocol KeychainBackend: Sendable {
    nonisolated func copyMatching(_ query: [String: Any]) -> (status: OSStatus, item: Data?)
    nonisolated func add(_ attributes: [String: Any]) -> OSStatus
    nonisolated func update(query: [String: Any], attributes: [String: Any]) -> OSStatus
    nonisolated func delete(_ query: [String: Any]) -> OSStatus
}

nonisolated struct SecItemKeychainBackend: KeychainBackend {
    init() {}

    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, item: Data?) {
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func update(query: [String: Any], attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}

nonisolated struct KeychainStore: Sendable {
    static let defaultService = "space.pkarpovich.edith"
    static let defaultAccount = "anthropic-api-key"

    let service: String
    let account: String
    let backend: any KeychainBackend

    init(
        service: String = KeychainStore.defaultService,
        account: String = KeychainStore.defaultAccount,
        backend: any KeychainBackend = SecItemKeychainBackend()
    ) {
        self.service = service
        self.account = account
        self.backend = backend
    }

    func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        let result = backend.copyMatching(query)
        guard result.status == errSecSuccess, let data = result.item else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func write(_ value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updateStatus = backend.update(query: baseQuery, attributes: updateAttributes)
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus != errSecItemNotFound {
            throw KeychainError.unexpectedStatus(updateStatus)
        }
        var addAttributes = baseQuery
        addAttributes[kSecValueData as String] = data
        addAttributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = backend.add(addAttributes)
        guard addStatus == errSecSuccess else {
            throw KeychainError.unexpectedStatus(addStatus)
        }
    }

    func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = backend.delete(query)
        if status == errSecSuccess || status == errSecItemNotFound {
            return
        }
        throw KeychainError.unexpectedStatus(status)
    }
}
