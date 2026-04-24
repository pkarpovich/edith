import AppKit
import Foundation
import Testing
@testable import edith

struct PasteboardSnapshotTests {
    private static func makePasteboard() -> NSPasteboard {
        NSPasteboard.withUniqueName()
    }

    @Test
    func captureEmptyPasteboardYieldsNoItems() {
        let pb = Self.makePasteboard()
        pb.clearContents()
        let snapshot = PasteboardSnapshot.capture(from: pb)
        #expect(snapshot.items.isEmpty)
    }

    @Test
    func stringRoundTripRestoresOriginalAfterMutation() {
        let pb = Self.makePasteboard()
        pb.clearContents()
        pb.setString("hello", forType: .string)

        let snapshot = PasteboardSnapshot.capture(from: pb)

        pb.clearContents()
        pb.setString("mutated", forType: .string)
        #expect(pb.string(forType: .string) == "mutated")

        snapshot.apply(to: pb)
        #expect(pb.string(forType: .string) == "hello")
    }

    @Test
    func multipleTypesOnOneItemAreRestored() {
        let pb = Self.makePasteboard()
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setString("plain", forType: .string)
        item.setString("<b>rich</b>", forType: .html)
        pb.writeObjects([item])

        let snapshot = PasteboardSnapshot.capture(from: pb)

        pb.clearContents()
        pb.setString("mutated", forType: .string)

        snapshot.apply(to: pb)
        #expect(pb.string(forType: .string) == "plain")
        #expect(pb.string(forType: .html) == "<b>rich</b>")
    }

    @Test
    func binaryPayloadIsPreservedByteForByte() {
        let pb = Self.makePasteboard()
        pb.clearContents()
        let bytes = Data([0x00, 0x01, 0x02, 0xFE, 0xFF])
        let customType = NSPasteboard.PasteboardType("space.pkarpovich.edith.tests.binary")
        let item = NSPasteboardItem()
        item.setData(bytes, forType: customType)
        pb.writeObjects([item])

        let snapshot = PasteboardSnapshot.capture(from: pb)

        pb.clearContents()
        pb.setString("overwrite", forType: .string)

        snapshot.apply(to: pb)
        #expect(pb.data(forType: customType) == bytes)
    }

    @Test
    func applyEmptySnapshotClearsPasteboard() {
        let pb = Self.makePasteboard()
        let emptySnapshot = PasteboardSnapshot(items: [])

        pb.clearContents()
        pb.setString("something", forType: .string)

        emptySnapshot.apply(to: pb)
        #expect(pb.string(forType: .string) == nil)
    }

    @Test
    func multipleItemsAreRestoredInOrderWithPayloads() {
        let pb = Self.makePasteboard()
        pb.clearContents()
        let first = NSPasteboardItem()
        first.setString("first", forType: .string)
        let second = NSPasteboardItem()
        second.setString("second", forType: .string)
        pb.writeObjects([first, second])

        let snapshot = PasteboardSnapshot.capture(from: pb)
        #expect(snapshot.items.count == 2)

        pb.clearContents()
        pb.setString("mutated", forType: .string)

        snapshot.apply(to: pb)
        let restored = pb.pasteboardItems ?? []
        #expect(restored.count == 2)
        #expect(restored.first?.string(forType: .string) == "first")
        #expect(restored.last?.string(forType: .string) == "second")
    }
}
