import Foundation
import Testing
@testable import edith

private func event(_ name: String, data: String) -> String {
    return "event: \(name)\ndata: \(data)\n\n"
}

struct AnthropicSSEParserTests {
    @Test
    func wellFormedTextDeltaYieldsTextDelta() {
        var parser = AnthropicSSEParser()
        let chunk = event(
            "content_block_delta",
            data: #"{"type": "content_block_delta","index": 0,"delta": {"type": "text_delta", "text": "ello frien"}}"#
        )
        let events = parser.feed(chunk)
        #expect(events == [.textDelta("ello frien")])
    }

    @Test
    func messageStopYieldsMessageStop() {
        var parser = AnthropicSSEParser()
        let chunk = event("message_stop", data: #"{"type": "message_stop"}"#)
        let events = parser.feed(chunk)
        #expect(events == [.messageStop])
    }

    @Test
    func errorEventYieldsError() {
        var parser = AnthropicSSEParser()
        let chunk = event(
            "error",
            data: #"{"type": "error", "error": {"type": "overloaded_error", "message": "Overloaded"}}"#
        )
        let events = parser.feed(chunk)
        #expect(events == [.error(type: "overloaded_error", message: "Overloaded")])
    }

    @Test
    func pingEventProducesNoOutput() {
        var parser = AnthropicSSEParser()
        let chunk = event("ping", data: #"{"type": "ping"}"#)
        let events = parser.feed(chunk)
        #expect(events.isEmpty)
    }

    @Test
    func unknownEventNameProducesNoOutputAndDoesNotThrow() {
        var parser = AnthropicSSEParser()
        let chunk = event("future_thing", data: #"{"foo": "bar"}"#)
        let events = parser.feed(chunk)
        #expect(events.isEmpty)
    }

    @Test
    func messageStartIsSilentlySkipped() {
        var parser = AnthropicSSEParser()
        let chunk = event("message_start", data: #"{"type": "message_start", "message": {}}"#)
        let events = parser.feed(chunk)
        #expect(events.isEmpty)
    }

    @Test
    func contentBlockStartAndStopAreSkipped() {
        var parser = AnthropicSSEParser()
        let chunk = event("content_block_start", data: #"{"type": "content_block_start", "index": 0}"#)
            + event("content_block_stop", data: #"{"type": "content_block_stop", "index": 0}"#)
        let events = parser.feed(chunk)
        #expect(events.isEmpty)
    }

    @Test
    func messageDeltaIsSkipped() {
        var parser = AnthropicSSEParser()
        let chunk = event(
            "message_delta",
            data: #"{"type": "message_delta", "delta": {"stop_reason": "end_turn"}}"#
        )
        let events = parser.feed(chunk)
        #expect(events.isEmpty)
    }

    @Test
    func nonTextContentBlockDeltaIsSilentlyDropped() {
        var parser = AnthropicSSEParser()
        let chunk = event(
            "content_block_delta",
            data: #"{"type": "content_block_delta","index": 0,"delta": {"type": "input_json_delta", "partial_json": "{\"x\":"}}"#
        )
        let events = parser.feed(chunk)
        #expect(events.isEmpty)
    }

    @Test
    func malformedJSONIsLoggedAndParserContinues() {
        var parser = AnthropicSSEParser()
        let chunk = event("content_block_delta", data: "{not valid json")
            + event(
                "content_block_delta",
                data: #"{"type": "content_block_delta","index": 0,"delta": {"type": "text_delta", "text": "ok"}}"#
            )
        let events = parser.feed(chunk)
        #expect(events == [.textDelta("ok")])
    }

    @Test
    func multipleEventsInOneFeedAreYieldedInOrder() {
        var parser = AnthropicSSEParser()
        let chunk = event(
            "content_block_delta",
            data: #"{"type": "content_block_delta","index": 0,"delta": {"type": "text_delta", "text": "foo"}}"#
        )
            + event(
                "content_block_delta",
                data: #"{"type": "content_block_delta","index": 0,"delta": {"type": "text_delta", "text": "bar"}}"#
            )
            + event("message_stop", data: #"{"type": "message_stop"}"#)
        let events = parser.feed(chunk)
        #expect(events == [.textDelta("foo"), .textDelta("bar"), .messageStop])
    }

    @Test
    func partialBufferAcrossTwoFeedsYieldsCompleteEvent() {
        var parser = AnthropicSSEParser()
        let first = #"event: content_block_delta"# + "\n"
            + #"data: {"type": "content_block_delta","index": 0,"delta": {"type": "text_de"#
        let second = #"lta", "text": "hi"}}"# + "\n\n"

        let firstEvents = parser.feed(first)
        #expect(firstEvents.isEmpty)

        let secondEvents = parser.feed(second)
        #expect(secondEvents == [.textDelta("hi")])
    }

    @Test
    func splitOnEventBoundaryIsAccumulated() {
        var parser = AnthropicSSEParser()
        let full = event(
            "content_block_delta",
            data: #"{"type": "content_block_delta","index": 0,"delta": {"type": "text_delta", "text": "a"}}"#
        )
            + event(
                "content_block_delta",
                data: #"{"type": "content_block_delta","index": 0,"delta": {"type": "text_delta", "text": "b"}}"#
            )
        let cut = full.index(full.startIndex, offsetBy: full.count - 4)
        let first = String(full[..<cut])
        let second = String(full[cut...])

        let firstEvents = parser.feed(first)
        let secondEvents = parser.feed(second)
        #expect(firstEvents + secondEvents == [.textDelta("a"), .textDelta("b")])
    }

    @Test
    func multilineDataPayloadIsConcatenated() {
        var parser = AnthropicSSEParser()
        let chunk = "event: content_block_delta\n"
            + #"data: {"type": "content_block_delta","index": 0,"# + "\n"
            + #"data: "delta": {"type": "text_delta", "text": "multi"}}"# + "\n\n"
        let events = parser.feed(chunk)
        #expect(events == [.textDelta("multi")])
    }

    @Test
    func emptyInputYieldsNoEvents() {
        var parser = AnthropicSSEParser()
        let events = parser.feed("")
        #expect(events.isEmpty)
    }

    @Test
    func dataChunkInputProducesEvents() {
        var parser = AnthropicSSEParser()
        let chunk = event(
            "content_block_delta",
            data: #"{"type": "content_block_delta","index": 0,"delta": {"type": "text_delta", "text": "x"}}"#
        )
        let events = parser.feed(Data(chunk.utf8))
        #expect(events == [.textDelta("x")])
    }

    @Test
    func commentLinesAreIgnored() {
        var parser = AnthropicSSEParser()
        let chunk = ": keepalive comment\n"
            + event(
                "content_block_delta",
                data: #"{"type": "content_block_delta","index": 0,"delta": {"type": "text_delta", "text": "z"}}"#
            )
        let events = parser.feed(chunk)
        #expect(events == [.textDelta("z")])
    }

    @Test
    func crlfTerminatedFramesYieldEvents() {
        var parser = AnthropicSSEParser()
        let body = #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"hi"}}"#
        var bytes = Array("event: content_block_delta".utf8)
        bytes.append(contentsOf: [0x0D, 0x0A])
        bytes.append(contentsOf: Array(body.utf8))
        bytes.append(contentsOf: [0x0D, 0x0A, 0x0D, 0x0A])
        let events = parser.feed(Data(bytes))
        #expect(events == [.textDelta("hi")])
    }

    @Test
    func crlfLinesWithLFLFTerminatorStripsTrailingCR() {
        var parser = AnthropicSSEParser()
        var bytes = Array("event: content_block_delta".utf8)
        bytes.append(contentsOf: [0x0D, 0x0A])
        bytes.append(contentsOf: Array(#"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"clean"}}"#.utf8))
        bytes.append(contentsOf: [0x0D, 0x0A, 0x0A])
        let events = parser.feed(Data(bytes))
        #expect(events == [.textDelta("clean")])
    }

    @Test
    func mixedCRLFAndLFTerminatorsAcrossEvents() {
        var parser = AnthropicSSEParser()
        let firstBody = #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"a"}}"#
        var bytes = Array("event: content_block_delta".utf8)
        bytes.append(contentsOf: [0x0D, 0x0A])
        bytes.append(contentsOf: Array(firstBody.utf8))
        bytes.append(contentsOf: [0x0D, 0x0A, 0x0D, 0x0A])
        bytes.append(contentsOf: Array(event(
            "content_block_delta",
            data: #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"b"}}"#
        ).utf8))
        let events = parser.feed(Data(bytes))
        #expect(events == [.textDelta("a"), .textDelta("b")])
    }
}
