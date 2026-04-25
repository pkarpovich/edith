import Foundation
import Testing
@testable import edith

struct ClaudeCLIProviderArgumentsTests {
    @Test
    func defaultsWithNoModelOrEffort() {
        let args = ClaudeCLIProvider.arguments(model: nil, effort: nil)
        #expect(args == ["-p", "--output-format=text"])
    }

    @Test
    func includesModelFlagWhenProvided() {
        let args = ClaudeCLIProvider.arguments(model: "haiku", effort: nil)
        #expect(args == ["-p", "--output-format=text", "--model", "haiku"])
    }

    @Test
    func includesEffortFlagWhenProvided() {
        let args = ClaudeCLIProvider.arguments(model: nil, effort: "low")
        #expect(args == ["-p", "--output-format=text", "--effort", "low"])
    }

    @Test
    func includesBothFlagsWhenProvided() {
        let args = ClaudeCLIProvider.arguments(model: "sonnet", effort: "high")
        #expect(args == ["-p", "--output-format=text", "--model", "sonnet", "--effort", "high"])
    }

    @Test
    func emptyModelStringIsTreatedAsAbsent() {
        let args = ClaudeCLIProvider.arguments(model: "", effort: nil)
        #expect(args == ["-p", "--output-format=text"])
    }

    @Test
    func emptyEffortStringIsTreatedAsAbsent() {
        let args = ClaudeCLIProvider.arguments(model: nil, effort: "")
        #expect(args == ["-p", "--output-format=text"])
    }

    @Test
    func argumentsDoNotContainPromptText() {
        let args = ClaudeCLIProvider.arguments(model: "opus", effort: "max")
        #expect(!args.contains("a prompt"))
        #expect(!args.contains { $0.contains("selection") })
    }
}

struct ClaudeCLIProviderEnvironmentOverridesTests {
    @Test
    func removesAnthropicApiKey() {
        let overrides = ClaudeCLIProvider.environmentOverrides(
            home: "/Users/tester",
            existingPath: "/usr/bin:/bin"
        )
        #expect(overrides.keys.contains("ANTHROPIC_API_KEY"))
        if let value = overrides["ANTHROPIC_API_KEY"] {
            #expect(value == nil)
        } else {
            Issue.record("ANTHROPIC_API_KEY override missing")
        }
    }

    @Test
    func removesClaudecodeFlag() {
        let overrides = ClaudeCLIProvider.environmentOverrides(
            home: "/Users/tester",
            existingPath: "/usr/bin:/bin"
        )
        #expect(overrides.keys.contains("CLAUDECODE"))
        if let value = overrides["CLAUDECODE"] {
            #expect(value == nil)
        } else {
            Issue.record("CLAUDECODE override missing")
        }
    }

    @Test
    func setsPathWithExtras() {
        let overrides = ClaudeCLIProvider.environmentOverrides(
            home: "/Users/tester",
            existingPath: "/usr/bin:/bin"
        )
        guard let pathOverride = overrides["PATH"], let path = pathOverride else {
            Issue.record("PATH override missing or nil")
            return
        }
        let parts = path.split(separator: ":").map(String.init)
        #expect(parts.contains("/opt/homebrew/bin"))
        #expect(parts.contains("/Users/tester/.bun/bin"))
        #expect(parts.contains("/Users/tester/.local/bin"))
        #expect(parts.contains("/usr/local/bin"))
        #expect(parts.contains("/usr/bin"))
        #expect(parts.contains("/bin"))
    }

    @Test
    func preservesExistingPathPrefixOrder() {
        let overrides = ClaudeCLIProvider.environmentOverrides(
            home: "/Users/tester",
            existingPath: "/custom/first:/custom/second"
        )
        guard let pathOverride = overrides["PATH"], let path = pathOverride else {
            Issue.record("PATH override missing or nil")
            return
        }
        let parts = path.split(separator: ":").map(String.init)
        #expect(parts.first == "/custom/first")
        #expect(parts.dropFirst().first == "/custom/second")
    }

    @Test
    func dedupesRepeatedPathEntries() {
        let overrides = ClaudeCLIProvider.environmentOverrides(
            home: "/Users/tester",
            existingPath: "/opt/homebrew/bin:/usr/bin"
        )
        guard let pathOverride = overrides["PATH"], let path = pathOverride else {
            Issue.record("PATH override missing or nil")
            return
        }
        let parts = path.split(separator: ":").map(String.init)
        let homebrewCount = parts.filter { $0 == "/opt/homebrew/bin" }.count
        let usrBinCount = parts.filter { $0 == "/usr/bin" }.count
        #expect(homebrewCount == 1)
        #expect(usrBinCount == 1)
    }

    @Test
    func handlesEmptyExistingPath() {
        let overrides = ClaudeCLIProvider.environmentOverrides(
            home: "/Users/tester",
            existingPath: ""
        )
        guard let pathOverride = overrides["PATH"], let path = pathOverride else {
            Issue.record("PATH override missing or nil")
            return
        }
        let parts = path.split(separator: ":").map(String.init)
        #expect(parts.first == "/opt/homebrew/bin")
        #expect(parts.contains("/bin"))
    }
}
