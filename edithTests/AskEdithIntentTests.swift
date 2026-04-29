import Foundation
import Testing
import AppIntents
@testable import edith

struct AskEdithIntentTests {
    @Test
    func titleIsAskEdith() {
        #expect(String(localized: AskEdithIntent.title) == "Ask Edith")
    }

    @Test
    func supportedModesIsBackground() {
        #expect(AskEdithIntent.supportedModes == .background)
    }
}

struct AskEdithIntentPrepareProviderTests {
    private static func writeTempPrompt(_ contents: String) throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("edith-prepare-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("prompt.txt")
        try contents.write(to: file, atomically: true, encoding: .utf8)
        return file.path
    }

    @Test
    func prepareDefaultsProviderToCli() throws {
        let path = try Self.writeTempPrompt("Fix:\n{{selection}}")
        let prepared = try AskEdithIntent.prepare(path: path, selection: "abc")
        #expect(prepared.provider == .cli)
    }

    @Test
    func prepareReturnsCliWhenFrontmatterRequestsCli() throws {
        let path = try Self.writeTempPrompt("""
        ---
        provider: cli
        ---
        Fix:
        {{selection}}
        """)
        let prepared = try AskEdithIntent.prepare(path: path, selection: "abc")
        #expect(prepared.provider == .cli)
    }

    @Test
    func prepareReturnsApiWhenFrontmatterRequestsApi() throws {
        let path = try Self.writeTempPrompt("""
        ---
        provider: api
        model: haiku
        ---
        Fix:
        {{selection}}
        """)
        let prepared = try AskEdithIntent.prepare(path: path, selection: "abc")
        #expect(prepared.provider == .api)
        #expect(prepared.model == "haiku")
    }

    @Test
    func prepareUnknownProviderFallsBackToCli() throws {
        let path = try Self.writeTempPrompt("""
        ---
        provider: weird
        ---
        Fix:
        {{selection}}
        """)
        let prepared = try AskEdithIntent.prepare(path: path, selection: "abc")
        #expect(prepared.provider == .cli)
    }

    @Test
    func preparePreservesPinnedAnthropicModelId() throws {
        let path = try Self.writeTempPrompt("""
        ---
        provider: api
        model: claude-haiku-4-5-20251001
        ---
        Fix:
        {{selection}}
        """)
        let prepared = try AskEdithIntent.prepare(path: path, selection: "abc")
        #expect(prepared.model == "claude-haiku-4-5-20251001")
    }

    @Test
    func makeProviderReturnsClaudeCLIForCli() {
        let provider = AskEdithIntent.makeProvider(kind: .cli)
        #expect(provider is ClaudeCLIProvider)
    }

    @Test
    func makeProviderReturnsAnthropicAPIForApi() {
        let provider = AskEdithIntent.makeProvider(kind: .api)
        #expect(provider is AnthropicAPIProvider)
    }
}
