import AppKit
import CoreGraphics
import Foundation
import os

enum Paster {
    static func paste(
        _ text: String,
        pasteboard: NSPasteboard = .general,
        restoreDelay: Duration = .milliseconds(250)
    ) {
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        postCommandV()

        Task { @MainActor in
            try? await Task.sleep(for: restoreDelay)
            snapshot.apply(to: pasteboard)
        }
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        else {
            Logger.edith.error("Paster: failed to create CGEvent for Cmd+V")
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
