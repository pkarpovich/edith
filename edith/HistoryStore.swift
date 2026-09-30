import Foundation
import SwiftData

enum HistoryStore {
    static func makeContainer(at url: URL) throws -> ModelContainer {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return try ModelContainer(for: EditRun.self, configurations: ModelConfiguration(url: url))
    }

    static var defaultURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "space.pkarpovich.edith", directoryHint: .isDirectory)
            .appending(path: "history.store", directoryHint: .notDirectory)
    }

    static func makeInMemoryContainer() throws -> ModelContainer {
        try ModelContainer(for: EditRun.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
}
