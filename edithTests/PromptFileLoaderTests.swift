import Foundation
import Testing
@testable import edith

struct PromptFileLoaderTests {
    @Test
    func loadReadsFileContents() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("prompt-loader-\(UUID().uuidString).txt")
        try "hello world".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let contents = try PromptFileLoader.load(path: url.path)
        #expect(contents == "hello world")
    }

    @Test
    func loadPreservesNewlines() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("prompt-loader-\(UUID().uuidString).txt")
        let body = "line1\nline2\n"
        try body.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let contents = try PromptFileLoader.load(path: url.path)
        #expect(contents == body)
    }

    @Test
    func loadThrowsIoFailureForMissingFile() {
        let path = "/tmp/edith-prompt-loader-missing-\(UUID().uuidString)"
        do {
            _ = try PromptFileLoader.load(path: path)
            Issue.record("expected ioFailure for missing file")
        } catch let error as PromptParserError {
            guard case .ioFailure(let reportedPath, let underlying) = error else {
                Issue.record("expected .ioFailure, got \(error)")
                return
            }
            #expect(reportedPath == path)
            #expect(!underlying.isEmpty)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test
    func loadExpandsLeadingTilde() throws {
        let home = NSHomeDirectory()
        let fileName = "edith-prompt-loader-\(UUID().uuidString).txt"
        let absolute = (home as NSString).appendingPathComponent(fileName)
        try "tilde-body".write(toFile: absolute, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: absolute) }

        let contents = try PromptFileLoader.load(path: "~/\(fileName)")
        #expect(contents == "tilde-body")
    }

    @Test
    func expandTildeReplacesLeadingTilde() {
        let result = PromptFileLoader.expandTilde("~/foo/bar")
        #expect(result == NSHomeDirectory() + "/foo/bar")
    }

    @Test
    func expandTildeLeavesAbsolutePathsUnchanged() {
        let result = PromptFileLoader.expandTilde("/abs/path/file.txt")
        #expect(result == "/abs/path/file.txt")
    }

    @Test
    func expandTildeDoesNotExpandTildeUserForm() {
        let result = PromptFileLoader.expandTilde("~user/foo")
        #expect(result == "~user/foo")
    }

    @Test
    func expandTildeLeavesBareTildeUnchanged() {
        let result = PromptFileLoader.expandTilde("~")
        #expect(result == "~")
    }

    @Test
    func expandTildeLeavesRelativePathsUnchanged() {
        let result = PromptFileLoader.expandTilde("relative/path.txt")
        #expect(result == "relative/path.txt")
    }
}
