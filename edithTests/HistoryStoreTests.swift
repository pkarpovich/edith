import Foundation
import SwiftData
import Testing
@testable import edith

@MainActor
struct HistoryStoreTests {
    @Test
    func defaultURLPointsAtAppSupportHistoryStore() {
        let url = HistoryStore.defaultURL
        #expect(url.lastPathComponent == "history.store")
        #expect(url.deletingLastPathComponent().lastPathComponent == "space.pkarpovich.edith")
        #expect(url.deletingLastPathComponent().deletingLastPathComponent() == URL.applicationSupportDirectory)
    }

    @Test
    func makeContainerCreatesDirectoryAndPersistsRuns() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "edith-history-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "nested/history.store")

        let writer = try HistoryStore.makeContainer(at: url)
        let context = ModelContext(writer)
        context.insert(EditRun(promptPath: "p", promptName: nil, provider: nil, model: nil, effort: nil, original: "orig"))
        try context.save()

        let reader = try HistoryStore.makeContainer(at: url)
        let runs = try ModelContext(reader).fetch(FetchDescriptor<EditRun>())
        #expect(runs.map(\.original) == ["orig"])
    }

    @Test
    func makeInMemoryContainerStartsEmpty() throws {
        let container = try HistoryStore.makeInMemoryContainer()
        let runs = try ModelContext(container).fetch(FetchDescriptor<EditRun>())
        #expect(runs.isEmpty)
    }
}
