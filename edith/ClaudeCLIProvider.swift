import Foundation
import Subprocess

nonisolated struct ClaudeCLIProvider: AIProvider {
    private static let outputLimit: Int = 1 * 1024 * 1024

    func run(prompt: String, model: String?, effort: String?) async throws -> String {
        do {
            let result = try await Subprocess.run(
                .name("claude"),
                arguments: Arguments(Self.arguments(model: model, effort: effort)),
                environment: Self.environment(),
                input: .string(prompt),
                output: .string(limit: Self.outputLimit),
                error: .string(limit: Self.outputLimit)
            )
            try Task.checkCancellation()

            switch result.terminationStatus {
            case .exited(let code) where code == 0:
                var stdout = result.standardOutput ?? ""
                while let last = stdout.last, last == "\n" || last == "\r" {
                    stdout.removeLast()
                }
                if stdout.isEmpty { throw AIProviderError.emptyOutput }
                return stdout
            case .exited(let code):
                let stderr = (result.standardError ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw AIProviderError.nonZeroExit(code: Int32(code), stderr: stderr)
            case .signaled(let signal):
                let stderr = (result.standardError ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw AIProviderError.terminatedBySignal(signal: Int32(signal), stderr: stderr)
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

    static func arguments(model: String?, effort: String?) -> [String] {
        var args: [String] = ["-p", "--output-format=text"]
        if let model, !model.isEmpty {
            args.append("--model")
            args.append(model)
        }
        if let effort, !effort.isEmpty {
            args.append("--effort")
            args.append(effort)
        }
        return args
    }

    static func environmentOverrides(
        home: String = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory(),
        existingPath: String = ProcessInfo.processInfo.environment["PATH"] ?? ""
    ) -> [String: String?] {
        let extras = [
            "/opt/homebrew/bin",
            "\(home)/.bun/bin",
            "\(home)/.local/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
        ]
        let parts = existingPath.split(separator: ":", omittingEmptySubsequences: true).map(String.init)
        var seen = Set<String>()
        var combined: [String] = []
        for path in parts + extras where seen.insert(path).inserted {
            combined.append(path)
        }
        return [
            "PATH": combined.joined(separator: ":"),
            "ANTHROPIC_API_KEY": nil,
            "CLAUDECODE": nil,
        ]
    }

    static func environment() -> Environment {
        let overrides = environmentOverrides()
        let pathValue = overrides["PATH"].flatMap { $0 } ?? ""
        let dict: [Environment.Key: String?] = [
            "PATH": pathValue,
            "ANTHROPIC_API_KEY": nil,
            "CLAUDECODE": nil,
        ]
        return .inherit.updating(dict)
    }
}
