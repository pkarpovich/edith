import AppKit
import CoreGraphics
import Foundation
import os

enum Paster {
    @discardableResult
    static func paste(
        _ text: String,
        pasteboard: NSPasteboard = .general,
        restoreDelay: Duration = .milliseconds(250)
    ) -> Bool {
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        pasteboard.clearContents()
        if !pasteboard.setString(text, forType: .string) {
            Logger.edith.error("Paster: setString returned false; aborting paste")
            snapshot.apply(to: pasteboard)
            return false
        }
        let expectedChangeCount = pasteboard.changeCount

        let posted = postCommandV()
        if !posted {
            snapshot.apply(to: pasteboard)
            return false
        }

        Task { @MainActor in
            try? await Task.sleep(for: restoreDelay)
            guard pasteboard.changeCount == expectedChangeCount else {
                Logger.edith.info("Paster: pasteboard mutated externally; skipping restore")
                return
            }
            snapshot.apply(to: pasteboard)
        }
        return true
    }

    private static func postCommandV() -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        else {
            Logger.edith.error("Paster: failed to create CGEvent for Cmd+V")
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
