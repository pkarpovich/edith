import Foundation
import Observation

enum OverlayState: Equatable, Sendable {
    case processing(original: String)
    case ready(original: String, result: String)
    case error(original: String, message: String)

    var original: String {
        switch self {
        case .processing(let original): return original
        case .ready(let original, _): return original
        case .error(let original, _): return original
        }
    }

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

@MainActor
@Observable
final class OverlayStateModel {
    var state: OverlayState

    init(initial: OverlayState) {
        self.state = initial
    }
}
