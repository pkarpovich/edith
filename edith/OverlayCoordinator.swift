import AppKit
import SwiftUI
import os

@MainActor
final class OverlayCoordinator {
    enum Outcome: Sendable, Equatable {
        case confirmed(String)
        case dismissed
    }

    private var panel: OverlayPanel?
    private var monitor: Any?
    private var continuation: CheckedContinuation<Outcome, Never>?

    func present(original: String, result: String) async -> Outcome {
        await withCheckedContinuation { continuation in
            self.continuation = continuation

            let hosting = NSHostingView(rootView: OverlayView(original: original, result: result))
            let fitting = hosting.fittingSize
            let size = NSSize(width: max(fitting.width, 640), height: max(fitting.height, 180))
            let rect = Self.centeredRect(for: size)

            let panel = OverlayPanel(contentRect: rect)
            panel.contentView = hosting
            self.panel = panel

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                switch event.keyCode {
                case 36, 76:
                    self.resolve(.confirmed(result))
                    return nil
                case 53:
                    self.resolve(.dismissed)
                    return nil
                default:
                    return event
                }
            }

            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func resolve(_ outcome: Outcome) {
        guard let continuation else { return }
        self.continuation = nil
        teardown()
        if case .confirmed(let text) = outcome {
            Paster.paste(text)
        }
        let label: String = {
            switch outcome {
            case .confirmed: return "confirmed"
            case .dismissed: return "dismissed"
            }
        }()
        Logger.edith.info("OverlayCoordinator resolved: \(label, privacy: .public)")
        continuation.resume(returning: outcome)
    }

    private func teardown() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        panel?.orderOut(nil)
        panel = nil
    }

    private static func centeredRect(for size: NSSize) -> NSRect {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = screenFrame.midX - size.width / 2
        let y = screenFrame.midY - size.height / 2
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
}
