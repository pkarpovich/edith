import Foundation
import Observation

enum OverlayState: Equatable, Sendable {
    case processing(original: String)
    case streaming(original: String, partial: String)
    case ready(original: String, result: String)
    case error(original: String, message: String)

    var original: String {
        switch self {
        case .processing(let original): return original
        case .streaming(let original, _): return original
        case .ready(let original, _): return original
        case .error(let original, _): return original
        }
    }
}

@MainActor
@Observable
final class OverlayStateModel {
    var state: OverlayState
    let promptName: String?
    let modelLabel: String?

    init(initial: OverlayState, promptName: String? = nil, modelLabel: String? = nil) {
        self.state = initial
        self.promptName = promptName
        self.modelLabel = modelLabel
    }
}
