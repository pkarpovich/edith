import Foundation
import SwiftData
import Testing
@testable import edith

private func makeContainer() throws -> ModelContainer {
    try ModelContainer(for: EditRun.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
}

private func fetchAll(_ container: ModelContainer) throws -> [EditRun] {
    let context = ModelContext(container)
    return try context.fetch(FetchDescriptor<EditRun>(sortBy: [SortDescriptor(\.createdAt)]))
}

@MainActor
private func startRun(_ recorder: RunRecorder, original: String = "orig") -> EditRun {
    recorder.start(
        promptPath: "~/.config/edith/fix-ru.txt",
        promptName: "fix-ru",
        provider: .api,
        model: "claude-sonnet-5-5",
        effort: "medium",
        original: original
    )
}

@MainActor
private func insertRun(
    _ context: ModelContext,
    original: String,
    secondsAgo: TimeInterval,
    result: String?,
    outcome: RunOutcome
) {
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
}

@MainActor
struct RunRecorderTests {
    @Test func startFinishResolvePersistsAllFields() throws {
        let container = try makeContainer()
        let recorder = RunRecorder(context: container.mainContext)

        let run = startRun(recorder)
        let response = ProviderResponse(text: "fixed", rawOutput: "{\"text\":\"fixed\"}", stopReason: "end_turn")
        recorder.finish(run, with: .finished(response, latencySeconds: 1.5))
        recorder.resolve(run, as: .confirmed)

        let stored = try #require(try fetchAll(container).first)
        #expect(stored.promptPath == "~/.config/edith/fix-ru.txt")
        #expect(stored.promptName == "fix-ru")
        #expect(stored.provider == "api")
        #expect(stored.model == "claude-sonnet-5-5")
        #expect(stored.effort == "medium")
        #expect(stored.original == "orig")
        #expect(stored.rawOutput == "{\"text\":\"fixed\"}")
        #expect(stored.result == "fixed")
        #expect(stored.stopReason == "end_turn")
        #expect(stored.latencySeconds == 1.5)
        #expect(stored.outcome == .confirmed)
        #expect(stored.outcomeRaw == "confirmed")
        #expect(stored.errorMessage == nil)
    }

    @Test func startLeavesRunPending() throws {
        let container = try makeContainer()
        let recorder = RunRecorder(context: container.mainContext)

        startRun(recorder)

        let stored = try #require(try fetchAll(container).first)
        #expect(stored.outcome == .pending)
        #expect(stored.result == nil)
    }

    @Test func finishSuccessKeepsOutcomePending() throws {
        let container = try makeContainer()
        let recorder = RunRecorder(context: container.mainContext)

        let run = startRun(recorder)
        recorder.finish(run, with: .finished(ProviderResponse(text: "a", rawOutput: "a", stopReason: nil), latencySeconds: 0.2))

        let stored = try #require(try fetchAll(container).first)
        #expect(stored.outcome == .pending)
        #expect(stored.stopReason == nil)
    }

    @Test func finishFailedKeepsRawOutputAndMessage() throws {
        let container = try makeContainer()
        let recorder = RunRecorder(context: container.mainContext)

        let run = startRun(recorder)
        recorder.finish(run, with: .failed(message: "Claude stopped at the token limit before finishing.", rawOutput: "{\"text\":\"par", stopReason: "max_tokens", latencySeconds: 2))

        let stored = try #require(try fetchAll(container).first)
        #expect(stored.outcome == .failed)
        #expect(stored.errorMessage == "Claude stopped at the token limit before finishing.")
        #expect(stored.rawOutput == "{\"text\":\"par")
        #expect(stored.stopReason == "max_tokens")
        #expect(stored.result == nil)
        #expect(stored.latencySeconds == 2)
    }

    @Test func finishCancelledChangesNothing() throws {
        let container = try makeContainer()
        let recorder = RunRecorder(context: container.mainContext)

        let run = startRun(recorder)
        recorder.finish(run, with: .cancelled)

        let stored = try #require(try fetchAll(container).first)
        #expect(stored.outcome == .pending)
        #expect(stored.latencySeconds == nil)
        #expect(stored.errorMessage == nil)
    }

    @Test func recordFailureWritesFailedRunWithoutProvider() throws {
        let container = try makeContainer()
        let recorder = RunRecorder(context: container.mainContext)

        recorder.recordFailure(promptPath: "missing.txt", promptName: "missing", original: "orig", message: "Could not read prompt file")

        let runs = try fetchAll(container)
        #expect(runs.count == 1)
        let stored = try #require(runs.first)
        #expect(stored.outcome == .failed)
        #expect(stored.provider == nil)
        #expect(stored.model == nil)
        #expect(stored.effort == nil)
        #expect(stored.promptPath == "missing.txt")
        #expect(stored.promptName == "missing")
        #expect(stored.original == "orig")
        #expect(stored.errorMessage == "Could not read prompt file")
    }

    @Test(arguments: [RunOutcome.confirmed, .dismissed, .pasteFailed])
    func resolveKeepsFailedRunFailed(_ outcome: RunOutcome) throws {
        let container = try makeContainer()
        let recorder = RunRecorder(context: container.mainContext)

        let run = startRun(recorder)
        recorder.finish(run, with: .failed(message: "boom", rawOutput: nil, stopReason: nil, latencySeconds: 0.1))
        recorder.resolve(run, as: outcome)

        let stored = try #require(try fetchAll(container).first)
        #expect(stored.outcome == .failed)
    }

    @Test func resolvePendingRunAsDismissed() throws {
        let container = try makeContainer()
        let recorder = RunRecorder(context: container.mainContext)

        let run = startRun(recorder)
        recorder.resolve(run, as: .dismissed)

        let stored = try #require(try fetchAll(container).first)
        #expect(stored.outcome == .dismissed)
    }

    @Test func retryProducesTwoRows() throws {
        let container = try makeContainer()
        let recorder = RunRecorder(context: container.mainContext)

        let first = startRun(recorder)
        recorder.finish(first, with: .failed(message: "boom", rawOutput: nil, stopReason: nil, latencySeconds: 0.1))
        let second = startRun(recorder)
        recorder.finish(second, with: .finished(ProviderResponse(text: "ok", rawOutput: "ok", stopReason: "end_turn"), latencySeconds: 0.3))
        recorder.resolve(second, as: .dismissed)

        recorder.resolve(first, as: .dismissed)

        let outcomes = try fetchAll(container).map(\.outcome)
        #expect(outcomes.count == 2)
        #expect(Set(outcomes) == [.failed, .dismissed])
    }

    @Test func latestRunWithResultSkipsNewerFailedRun() throws {
        let container = try makeContainer()
        let context = container.mainContext
        insertRun(context, original: "old", secondsAgo: 30, result: "old fixed", outcome: .confirmed)
        insertRun(context, original: "dismissed", secondsAgo: 20, result: "dismissed fixed", outcome: .dismissed)
        insertRun(context, original: "failed", secondsAgo: 10, result: nil, outcome: .failed)
        try context.save()

        let runs = try context.fetch(EditRun.latestRunWithResult)

        #expect(runs.count == 1)
        #expect(runs.first?.result == "dismissed fixed")
    }

    @Test func latestRunReturnsNewestRegardlessOfOutcome() throws {
        let container = try makeContainer()
        let context = container.mainContext
        insertRun(context, original: "old", secondsAgo: 30, result: "old fixed", outcome: .confirmed)
        insertRun(context, original: "failed", secondsAgo: 10, result: nil, outcome: .failed)
        insertRun(context, original: "middle", secondsAgo: 20, result: "m", outcome: .pasteFailed)
        try context.save()

        let runs = try context.fetch(EditRun.latestRun)

        #expect(runs.count == 1)
        #expect(runs.first?.original == "failed")
    }

    @Test func descriptorsReturnNothingOnEmptyStore() throws {
        let container = try makeContainer()
        let context = container.mainContext

        #expect(try context.fetch(EditRun.latestRun).isEmpty)
        #expect(try context.fetch(EditRun.latestRunWithResult).isEmpty)
    }

    @Test(arguments: RunOutcome.allCases)
    func outcomeRoundTripsThroughRawValue(_ outcome: RunOutcome) throws {
        let container = try makeContainer()
        let recorder = RunRecorder(context: container.mainContext)

        let run = startRun(recorder)
        recorder.resolve(run, as: outcome)

        let stored = try #require(try fetchAll(container).first)
        #expect(stored.outcome == outcome)
        #expect(stored.outcomeRaw == outcome.rawValue)
    }

    @Test func unknownOutcomeRawFallsBackToPending() {
        let run = EditRun(promptPath: "p", promptName: nil, provider: nil, model: nil, effort: nil, original: "orig")
        run.outcomeRaw = "bogus"

        #expect(run.outcome == .pending)
    }
}
