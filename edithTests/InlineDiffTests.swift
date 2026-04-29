import SwiftUI
import Testing
@testable import edith

private struct Segment: Equatable {
    let text: String
    let highlighted: Bool
}

private func segments(_ attributed: AttributedString) -> [Segment] {
    var out: [Segment] = []
    for run in attributed.runs {
        let text = String(attributed[run.range].characters)
        let highlighted = run.backgroundColor != nil
        out.append(Segment(text: text, highlighted: highlighted))
    }
    return out
}

@MainActor
@Suite struct InlineDiffTests {
    @Test func identicalStringsProduceNoHighlight() {
        let result = attributedDiff(original: "hello world", result: "hello world", insertColor: .green)
        #expect(segments(result) == [Segment(text: "hello world", highlighted: false)])
    }

    @Test func emptyStringsProduceEmpty() {
        let result = attributedDiff(original: "", result: "", insertColor: .green)
        #expect(segments(result) == [])
    }

    @Test func pureInsertionFromEmptyIsFullyHighlighted() {
        let result = attributedDiff(original: "", result: "hello", insertColor: .green)
        #expect(segments(result) == [Segment(text: "hello", highlighted: true)])
    }

    @Test func insertionInMiddleHighlightsOnlyInsertedRun() {
        let result = attributedDiff(original: "hello world", result: "hello big world", insertColor: .green)
        #expect(segments(result) == [
            Segment(text: "hello ", highlighted: false),
            Segment(text: "big ", highlighted: true),
            Segment(text: "world", highlighted: false),
        ])
    }

    @Test func pureDeletionProducesUnhighlightedResult() {
        let result = attributedDiff(original: "hello big world", result: "hello world", insertColor: .green)
        #expect(segments(result) == [Segment(text: "hello world", highlighted: false)])
    }

    @Test func replacementHighlightsOnlyInsertedCharacters() {
        let result = attributedDiff(original: "cat", result: "bat", insertColor: .green)
        #expect(segments(result) == [
            Segment(text: "b", highlighted: true),
            Segment(text: "at", highlighted: false),
        ])
    }

    @Test func adjacentInsertionsMergeIntoSingleRun() {
        let result = attributedDiff(original: "ac", result: "abbc", insertColor: .green)
        #expect(segments(result) == [
            Segment(text: "a", highlighted: false),
            Segment(text: "bb", highlighted: true),
            Segment(text: "c", highlighted: false),
        ])
    }

    @Test func cyrillicCapitalisationHighlightsInsertedGrapheme() {
        let result = attributedDiff(original: "привет", result: "Привет", insertColor: .green)
        #expect(segments(result) == [
            Segment(text: "П", highlighted: true),
            Segment(text: "ривет", highlighted: false),
        ])
    }

    @Test func emojiInsertionIsGraphemeAware() {
        let result = attributedDiff(original: "hi", result: "hi👋", insertColor: .green)
        #expect(segments(result) == [
            Segment(text: "hi", highlighted: false),
            Segment(text: "👋", highlighted: true),
        ])
    }

    @Test func punctuationInsertionInRussianSentence() {
        let result = attributedDiff(
            original: "привет как дела",
            result: "Привет, как дела?",
            insertColor: .green
        )
        let segs = segments(result)
        #expect(segs.contains(Segment(text: "П", highlighted: true)))
        #expect(segs.contains(Segment(text: ",", highlighted: true)))
        #expect(segs.contains(Segment(text: "?", highlighted: true)))
        let highlighted = segs.filter { $0.highlighted }.map(\.text).joined()
        #expect(!highlighted.contains("ривет"))
        let reconstructed = segs.map(\.text).joined()
        #expect(reconstructed == "Привет, как дела?")
    }
}
