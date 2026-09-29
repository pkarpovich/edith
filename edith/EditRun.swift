import Foundation
import SwiftData

nonisolated enum RunOutcome: String, Sendable, CaseIterable {
    case pending
    case confirmed
    case dismissed
    case pasteFailed
    case failed
}

@Model
final class EditRun {
    var createdAt: Date
    var promptPath: String
    var promptName: String?
    var provider: String?
    var model: String?
    var effort: String?
    var original: String
    var rawOutput: String?
    var result: String?
    var stopReason: String?
    var latencySeconds: Double?
    var outcomeRaw: String
    var errorMessage: String?

    var outcome: RunOutcome {
        get { RunOutcome(rawValue: outcomeRaw) ?? .pending }
        set { outcomeRaw = newValue.rawValue }
    }

    init(
        createdAt: Date = .now,
        promptPath: String,
        promptName: String?,
        provider: String?,
        model: String?,
        effort: String?,
        original: String,
        outcome: RunOutcome = .pending
    ) {
        self.createdAt = createdAt
        self.promptPath = promptPath
        self.promptName = promptName
        self.provider = provider
        self.model = model
        self.effort = effort
        self.original = original
        self.outcomeRaw = outcome.rawValue
    }

    static var latestRun: FetchDescriptor<EditRun> {
        var descriptor = FetchDescriptor<EditRun>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return descriptor
    }

    static var latestRunWithResult: FetchDescriptor<EditRun> {
        var descriptor = FetchDescriptor<EditRun>(
            predicate: #Predicate { $0.result != nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }
}
