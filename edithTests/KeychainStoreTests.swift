import Foundation
import Security
import Testing
@testable import edith

private final class FakeKeychainBackend: KeychainBackend, @unchecked Sendable {
    struct Entry {
        let service: String
        let account: String
        var data: Data
        var accessible: String?
    }

    private let lock = NSLock()
    private var storage: [Entry] = []
    var addError: OSStatus?
    var updateError: OSStatus?
    var deleteError: OSStatus?
    var copyError: OSStatus?

    func entries() -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, item: Data?) {
        if let copyError {
            return (copyError, nil)
        }
        let service = query[kSecAttrService as String] as? String
        let account = query[kSecAttrAccount as String] as? String
        lock.lock()
        defer { lock.unlock() }
        guard let entry = storage.first(where: { $0.service == service && $0.account == account }) else {
            return (errSecItemNotFound, nil)
        }
        return (errSecSuccess, entry.data)
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        if let addError {
            return addError
        }
        guard let service = attributes[kSecAttrService as String] as? String,
              let account = attributes[kSecAttrAccount as String] as? String,
              let data = attributes[kSecValueData as String] as? Data else {
            return errSecParam
        }
        lock.lock()
        defer { lock.unlock() }
        if storage.contains(where: { $0.service == service && $0.account == account }) {
            return errSecDuplicateItem
        }
        let accessible = attributes[kSecAttrAccessible as String] as? String
        storage.append(Entry(service: service, account: account, data: data, accessible: accessible))
        return errSecSuccess
    }

    func update(query: [String: Any], attributes: [String: Any]) -> OSStatus {
        if let updateError {
            return updateError
        }
        guard let service = query[kSecAttrService as String] as? String,
              let account = query[kSecAttrAccount as String] as? String,
              let data = attributes[kSecValueData as String] as? Data else {
            return errSecParam
        }
        lock.lock()
        defer { lock.unlock() }
        guard let index = storage.firstIndex(where: { $0.service == service && $0.account == account }) else {
            return errSecItemNotFound
        }
        storage[index].data = data
        return errSecSuccess
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        if let deleteError {
            return deleteError
        }
        guard let service = query[kSecAttrService as String] as? String,
              let account = query[kSecAttrAccount as String] as? String else {
            return errSecParam
        }
        lock.lock()
        defer { lock.unlock() }
        guard let index = storage.firstIndex(where: { $0.service == service && $0.account == account }) else {
            return errSecItemNotFound
        }
        storage.remove(at: index)
        return errSecSuccess
    }
}

struct KeychainStoreTests {
    @Test
    func readReturnsNilWhenItemAbsent() {
        let backend = FakeKeychainBackend()
        let store = KeychainStore(backend: backend)
        #expect(store.read() == nil)
    }

    @Test
    func writeThenReadReturnsValue() throws {
        let backend = FakeKeychainBackend()
        let store = KeychainStore(backend: backend)
        try store.write("sk-123")
        #expect(store.read() == "sk-123")
        let entries = backend.entries()
        #expect(entries.count == 1)
        #expect(entries[0].service == KeychainStore.defaultService)
        #expect(entries[0].account == KeychainStore.defaultAccount)
        #expect(entries[0].accessible == (kSecAttrAccessibleAfterFirstUnlock as String))
    }

    @Test
    func writeOverwritesExistingValue() throws {
        let backend = FakeKeychainBackend()
        let store = KeychainStore(backend: backend)
        try store.write("first")
        try store.write("second")
        #expect(store.read() == "second")
        #expect(backend.entries().count == 1)
    }

    @Test
    func deleteRemovesEntryAndReadReturnsNil() throws {
        let backend = FakeKeychainBackend()
        let store = KeychainStore(backend: backend)
        try store.write("sk-456")
        try store.delete()
        #expect(store.read() == nil)
        #expect(backend.entries().isEmpty)
    }

    @Test
    func deleteOnMissingItemDoesNotThrow() throws {
        let backend = FakeKeychainBackend()
        let store = KeychainStore(backend: backend)
        try store.delete()
    }

    @Test
    func writeBubblesUpAddError() {
        let backend = FakeKeychainBackend()
        backend.addError = errSecAuthFailed
        let store = KeychainStore(backend: backend)
        #expect(throws: KeychainError.unexpectedStatus(errSecAuthFailed)) {
            try store.write("value")
        }
    }

    @Test
    func writeBubblesUpUpdateError() throws {
        let backend = FakeKeychainBackend()
        let store = KeychainStore(backend: backend)
        try store.write("first")
        backend.updateError = errSecAuthFailed
        #expect(throws: KeychainError.unexpectedStatus(errSecAuthFailed)) {
            try store.write("second")
        }
    }

    @Test
    func deleteBubblesUpUnexpectedError() {
        let backend = FakeKeychainBackend()
        backend.deleteError = errSecAuthFailed
        let store = KeychainStore(backend: backend)
        #expect(throws: KeychainError.unexpectedStatus(errSecAuthFailed)) {
            try store.delete()
        }
    }

    @Test
    func readReturnsNilOnUnexpectedCopyStatus() {
        let backend = FakeKeychainBackend()
        backend.copyError = errSecAuthFailed
        let store = KeychainStore(backend: backend)
        #expect(store.read() == nil)
    }

    @Test
    func customServiceAndAccountAreRespected() throws {
        let backend = FakeKeychainBackend()
        let store = KeychainStore(service: "alt.service", account: "alt-account", backend: backend)
        try store.write("v")
        let entries = backend.entries()
        #expect(entries.count == 1)
        #expect(entries[0].service == "alt.service")
        #expect(entries[0].account == "alt-account")
    }
}
