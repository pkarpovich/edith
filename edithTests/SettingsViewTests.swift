import Foundation
import Security
import Testing
@testable import edith

private final class FakeKeychainBackend: KeychainBackend, @unchecked Sendable {
    struct Entry {
        let service: String
        let account: String
        var data: Data
    }

    private let lock = NSLock()
    private var storage: [Entry] = []
    var addError: OSStatus?
    var updateError: OSStatus?
    var deleteError: OSStatus?

    func entries() -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, item: Data?) {
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
        storage.append(Entry(service: service, account: account, data: data))
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

@MainActor
struct SettingsViewTests {
    private func makeModel(backend: FakeKeychainBackend = FakeKeychainBackend()) -> (SettingsModel, FakeKeychainBackend) {
        let store = KeychainStore(backend: backend)
        let model = SettingsModel(store: store)
        return (model, backend)
    }

    @Test
    func refreshStatusReportsNoKeyWhenAbsent() {
        let (model, _) = makeModel()
        model.refreshStatus()
        #expect(model.status == .noKey)
    }

    @Test
    func refreshStatusReportsKeySavedWhenPresent() throws {
        let backend = FakeKeychainBackend()
        try KeychainStore(backend: backend).write("seed")
        let model = SettingsModel(store: KeychainStore(backend: backend))
        model.refreshStatus()
        #expect(model.status == .keySaved)
    }

    @Test
    func refreshStatusReportsNoKeyWhenStoredValueIsEmpty() throws {
        let backend = FakeKeychainBackend()
        try KeychainStore(backend: backend).write("")
        let model = SettingsModel(store: KeychainStore(backend: backend))
        model.refreshStatus()
        #expect(model.status == .noKey)
    }

    @Test
    func saveWritesToKeychainAndClearsInput() {
        let (model, backend) = makeModel()
        model.keyInput = "sk-abc"
        model.save()
        #expect(model.status == .keySaved)
        #expect(model.keyInput == "")
        #expect(backend.entries().count == 1)
        #expect(String(data: backend.entries()[0].data, encoding: .utf8) == "sk-abc")
    }

    @Test
    func saveTrimsWhitespace() {
        let (model, backend) = makeModel()
        model.keyInput = "  sk-trim  "
        model.save()
        #expect(model.status == .keySaved)
        #expect(String(data: backend.entries()[0].data, encoding: .utf8) == "sk-trim")
    }

    @Test
    func saveRejectsEmptyInput() {
        let (model, backend) = makeModel()
        model.keyInput = "   "
        model.save()
        #expect(model.status == .empty)
        #expect(backend.entries().isEmpty)
    }

    @Test
    func saveSurfacesBackendError() {
        let backend = FakeKeychainBackend()
        backend.addError = errSecAuthFailed
        let model = SettingsModel(store: KeychainStore(backend: backend))
        model.keyInput = "sk-fails"
        model.save()
        if case .error(let message) = model.status {
            #expect(message.contains("unexpectedStatus"))
        } else {
            Issue.record("expected error status, got \(model.status)")
        }
        #expect(model.keyInput == "sk-fails")
    }

    @Test
    func clearRemovesEntryAndUpdatesStatus() throws {
        let backend = FakeKeychainBackend()
        try KeychainStore(backend: backend).write("seed")
        let model = SettingsModel(store: KeychainStore(backend: backend))
        model.refreshStatus()
        #expect(model.status == .keySaved)
        model.clear()
        #expect(model.status == .noKey)
        #expect(backend.entries().isEmpty)
    }

    @Test
    func clearOnEmptyKeychainStillReportsNoKey() {
        let (model, _) = makeModel()
        model.clear()
        #expect(model.status == .noKey)
    }

    @Test
    func clearSurfacesBackendError() {
        let backend = FakeKeychainBackend()
        backend.deleteError = errSecAuthFailed
        let model = SettingsModel(store: KeychainStore(backend: backend))
        model.clear()
        if case .error(let message) = model.status {
            #expect(message.contains("unexpectedStatus"))
        } else {
            Issue.record("expected error status, got \(model.status)")
        }
    }
}
