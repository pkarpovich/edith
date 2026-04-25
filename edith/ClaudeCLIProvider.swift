import Foundation
import Subprocess

nonisolated struct ClaudeCLIProvider: AIProvider {
    private static let outputLimit: Int = 1 * 1024 * 1024

    func run(prompt: String, input: String) async throws -> String {
        do {
            let result = try await Subprocess.run(
                .name("claude"),
                arguments: ["-p", prompt, "--output-format=text"],
                environment: Self.environment(),
                input: .string(input),
                output: .string(limit: Self.outputLimit),
                error: .string(limit: Self.outputLimit)
            )
            try Task.checkCancellation()

            switch result.terminationStatus {
            case .exited(let code) where code == 0:
                let stdout = (result.standardOutput ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if stdout.isEmpty { throw AIProviderError.emptyOutput }
                return stdout
            case .exited(let code), .signaled(let code):
                let stderr = (result.standardError ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw AIProviderError.nonZeroExit(code: Int32(code), stderr: stderr)
            }
        } catch is CancellationError {
            throw AIProviderError.cancelled
        } catch let error as SubprocessError {
            if error.code == .executableNotFound {
                throw AIProviderError.notFound
            }
            throw error
        }
    }

    static func environment() -> Environment {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        let extras = [
            "/opt/homebrew/bin",
            "\(home)/.bun/bin",
            "\(home)/.local/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
        ]
        let existing = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let parts = existing.split(separator: ":", omittingEmptySubsequences: true).map(String.init)
        var seen = Set<String>()
        var combined: [String] = []
        for path in parts + extras where seen.insert(path).inserted {
            combined.append(path)
        }
        return .inherit.updating([Environment.Key("PATH"): combined.joined(separator: ":")])
    }
}
