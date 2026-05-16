import SwiftUI
import Testing
@testable import edith

nonisolated fileprivate struct Segment: Equatable, CustomStringConvertible {
    let text: String
    let highlighted: Bool

    var description: String {
        "\(highlighted ? "[+]" : "[ ]")\(text)"
    }
}

nonisolated fileprivate func segments(_ attributed: AttributedString) -> [Segment] {
    var out: [Segment] = []
    for run in attributed.runs {
        let text = String(attributed[run.range].characters)
        let highlighted = run.backgroundColor != nil
        out.append(Segment(text: text, highlighted: highlighted))
    }
    return out
}

nonisolated fileprivate struct DiffCase: Sendable, CustomTestStringConvertible {
    let name: String
    let original: String
    let result: String
    let expected: [Segment]

    var testDescription: String { name }
}

@Suite nonisolated struct InlineDiffTests {
    fileprivate nonisolated static let cases: [DiffCase] = [
        DiffCase(name: "identical → no highlight",
                 original: "hello world", result: "hello world",
                 expected: [Segment(text: "hello world", highlighted: false)]),

        DiffCase(name: "both empty → empty",
                 original: "", result: "",
                 expected: []),

        DiffCase(name: "pure insertion from empty → all highlighted",
                 original: "", result: "hello",
                 expected: [Segment(text: "hello", highlighted: true)]),

        DiffCase(name: "insertion in middle → only inserted run highlighted",
                 original: "hello world", result: "hello big world",
                 expected: [
                    Segment(text: "hello ", highlighted: false),
                    Segment(text: "big ", highlighted: true),
                    Segment(text: "world", highlighted: false),
                 ]),

        DiffCase(name: "pure deletion → unhighlighted result",
                 original: "hello big world", result: "hello world",
                 expected: [Segment(text: "hello world", highlighted: false)]),

        DiffCase(name: "replacement → only inserted char highlighted",
                 original: "cat", result: "bat",
                 expected: [
                    Segment(text: "b", highlighted: true),
                    Segment(text: "at", highlighted: false),
                 ]),

        DiffCase(name: "adjacent insertions merge into single run",
                 original: "ac", result: "abbc",
                 expected: [
                    Segment(text: "a", highlighted: false),
                    Segment(text: "bb", highlighted: true),
                    Segment(text: "c", highlighted: false),
                 ]),

        DiffCase(name: "cyrillic capitalisation → grapheme highlighted",
                 original: "привет", result: "Привет",
                 expected: [
                    Segment(text: "П", highlighted: true),
                    Segment(text: "ривет", highlighted: false),
                 ]),

        DiffCase(name: "emoji insertion is grapheme-aware",
                 original: "hi", result: "hi👋",
                 expected: [
                    Segment(text: "hi", highlighted: false),
                    Segment(text: "👋", highlighted: true),
                 ]),

        DiffCase(name: "russian sentence with punctuation insertions",
                 original: "привет как дела", result: "Привет, как дела?",
                 expected: [
                    Segment(text: "П", highlighted: true),
                    Segment(text: "ривет", highlighted: false),
                    Segment(text: ",", highlighted: true),
                    Segment(text: " как дела", highlighted: false),
                    Segment(text: "?", highlighted: true),
                 ]),
    ]

    @Test(arguments: cases)
    fileprivate func diffProducesExpectedSegments(_ kase: DiffCase) {
        let attributed = attributedDiff(original: kase.original, result: kase.result, insertColor: .green)
        #expect(segments(attributed) == kase.expected)
    }

    @Test
    func insertColorParameterIsAppliedToHighlightedRuns() {
        let result = attributedDiff(original: "ac", result: "abc", insertColor: .red)
        let highlightedColors = result.runs.compactMap(\.backgroundColor)
        #expect(highlightedColors == [.red])
    }

    @Test
    func insertForegroundParameterIsAppliedToHighlightedRuns() {
        let result = attributedDiff(
            original: "ac", result: "abc",
            insertColor: .green, insertForeground: .yellow
        )
        let highlightedFgs = result.runs.compactMap(\.foregroundColor)
        #expect(highlightedFgs == [.yellow])
    }
}
