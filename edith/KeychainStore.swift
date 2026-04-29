import Foundation
import Security

enum KeychainError: Error, Equatable {
    case encodingFailed
    case unexpectedStatus(OSStatus)
}

protocol KeychainBackend: Sendable {
    nonisolated func copyMatching(_ query: [String: Any]) -> (status: OSStatus, item: Data?)
    nonisolated func add(_ attributes: [String: Any]) -> OSStatus
    nonisolated func update(query: [String: Any], attributes: [String: Any]) -> OSStatus
    nonisolated func delete(_ query: [String: Any]) -> OSStatus
}

struct SecItemKeychainBackend: KeychainBackend {
    nonisolated init() {}

    nonisolated func copyMatching(_ query: [String: Any]) -> (status: OSStatus, item: Data?) {
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }

    nonisolated func add(_ attributes: [String: Any]) -> OSStatus {
        return SecItemAdd(attributes as CFDictionary, nil)
    }

    nonisolated func update(query: [String: Any], attributes: [String: Any]) -> OSStatus {
        return SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    nonisolated func delete(_ query: [String: Any]) -> OSStatus {
        return SecItemDelete(query as CFDictionary)
    }
}

struct KeychainStore: Sendable {
    nonisolated static let defaultService = "space.pkarpovich.edith"
    nonisolated static let defaultAccount = "anthropic-api-key"

    let service: String
    let account: String
    let backend: any KeychainBackend

    nonisolated init(
        service: String = KeychainStore.defaultService,
        account: String = KeychainStore.defaultAccount,
        backend: any KeychainBackend = SecItemKeychainBackend()
    ) {
        self.service = service
        self.account = account
        self.backend = backend
    }

    nonisolated func read() -> String? {
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

    nonisolated func write(_ value: String) throws {
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

    nonisolated func delete() throws {
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
