import AppKit
import Foundation
import SwiftData
import Testing
@testable import edith

private func makeContainer() throws -> ModelContainer {
    try ModelContainer(for: EditRun.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
}

@MainActor
private func insertRun(
    _ context: ModelContext,
    original: String,
    secondsAgo: TimeInterval,
    result: String?,
    outcome: RunOutcome
) -> EditRun {
    let run = EditRun(
        createdAt: Date(timeIntervalSinceNow: -secondsAgo),
        promptPath: "p",
        promptName: nil,
        provider: ProviderKind.api.rawValue,
        model: nil,
        effort: nil,
        original: original,
        outcome: outcome
    )
    run.result = result
    context.insert(run)
    return run
}

@MainActor
struct HistoryMenuTests {
    @Test func copyReplacesPasteboardContentsWithText() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("stale", forType: .string)
        pasteboard.setString("<b>stale</b>", forType: .html)

        HistoryMenu.copy("fresh", to: pasteboard)

        #expect(pasteboard.string(forType: .string) == "fresh")
        #expect(pasteboard.string(forType: .html) == nil)
        #expect(pasteboard.pasteboardItems?.count == 1)
    }

    @Test func descriptorsPickRowsFromMixedOutcomes() throws {
        let container = try makeContainer()
        let context = container.mainContext
        _ = insertRun(context, original: "confirmed orig", secondsAgo: 40, result: "confirmed fixed", outcome: .confirmed)
        _ = insertRun(context, original: "dismissed orig", secondsAgo: 30, result: "dismissed fixed", outcome: .dismissed)
        _ = insertRun(context, original: "failed orig", secondsAgo: 10, result: nil, outcome: .failed)
        try context.save()

        let latest = try context.fetch(EditRun.latestRun)
        let latestWithResult = try context.fetch(EditRun.latestRunWithResult)

        #expect(latest.map(\.original) == ["failed orig"])
        #expect(latestWithResult.map(\.result) == ["dismissed fixed"])
    }

    @Test func copyingLatestRunsWritesExactResultAndOriginal() throws {
        let container = try makeContainer()
        let context = container.mainContext
        _ = insertRun(context, original: "old orig", secondsAgo: 20, result: "old fixed", outcome: .confirmed)
        _ = insertRun(context, original: "да, про приоритет", secondsAgo: 5, result: "Да, про приоритет.", outcome: .dismissed)
        try context.save()
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        let withResult = try #require(try context.fetch(EditRun.latestRunWithResult).first)
        HistoryMenu.copy(try #require(withResult.result), to: pasteboard)
        #expect(pasteboard.string(forType: .string) == "Да, про приоритет.")

        let latest = try #require(try context.fetch(EditRun.latestRun).first)
        HistoryMenu.copy(latest.original, to: pasteboard)
        #expect(pasteboard.string(forType: .string) == "да, про приоритет")
    }
}
