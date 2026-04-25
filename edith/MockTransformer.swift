import Foundation

nonisolated enum MockTransformer {
    static func transform(_ input: String) -> String {
        input.uppercased()
    }
}
