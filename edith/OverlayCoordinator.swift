import AppKit
import Carbon.HIToolbox
import SwiftUI
import os

@MainActor
final class OverlayCoordinator {
    enum Outcome: Sendable, Equatable {
        case confirmed(String)
        case dismissed
    }

    let model: OverlayStateModel

    private var panel: OverlayPanel?
    private var monitor: Any?
    private var continuation: CheckedContinuation<Outcome, Never>?
    private var driveFactory: (@MainActor () async -> Void)?
    private var activeDrive: Task<Void, Never>?

    init(initial: OverlayState, promptName: String? = nil, modelLabel: String? = nil) {
        self.model = OverlayStateModel(initial: initial, promptName: promptName, modelLabel: modelLabel)
    }

    func present(drive: (@MainActor () async -> Void)? = nil) async -> Outcome {
        await withCheckedContinuation { continuation in
            self.continuation = continuation

            let hosting = NSHostingView(rootView: OverlayView(model: model))
            let fitting = hosting.fittingSize
            let size = NSSize(
                width: max(fitting.width, DesignTokens.Window.width),
                height: max(fitting.height, 120)
            )
            let rect = ScreenResolver.centeredRect(for: size)

            let panel = OverlayPanel(contentRect: rect)
            panel.contentView = hosting
            self.panel = panel

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return self.handleKey(event)
            }

            if let drive {
                driveFactory = drive
                startDrive()
            }

            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        switch Int(event.keyCode) {
        case kVK_Return, kVK_ANSI_KeypadEnter:
            confirm()
            return nil
        case kVK_Escape:
            dismiss()
            return nil
        case kVK_ANSI_R where event.modifierFlags.contains(.command):
            retry()
            return nil
        default:
            return event
        }
    }

    func confirm() {
        guard case .ready(_, let result) = model.state else { return }
        resolve(.confirmed(result))
    }

    func dismiss() {
        resolve(.dismissed)
    }

    private func retry() {
        guard case .error = model.state, let driveFactory else { return }
        activeDrive?.cancel()
        model.state = .processing(original: model.state.original)
        self.driveFactory = driveFactory
        startDrive()
    }

    private func startDrive() {
        guard let driveFactory else { return }
        activeDrive = Task { @MainActor in
            await driveFactory()
        }
    }

    private func resolve(_ outcome: Outcome) {
        guard let continuation else { return }
        self.continuation = nil
        teardown()
        var pasteFailed = false
        if case .confirmed(let text) = outcome {
            if !Paster.paste(text) {
                pasteFailed = true
                NSSound.beep()
            }
        }
        let label: String = {
            switch outcome {
            case .confirmed: return pasteFailed ? "confirmed-paste-failed" : "confirmed"
            case .dismissed: return "dismissed"
            }
        }()
        if pasteFailed {
            Logger.edith.error("OverlayCoordinator resolved: \(label, privacy: .public)")
        } else {
            Logger.edith.info("OverlayCoordinator resolved: \(label, privacy: .public)")
        }
        continuation.resume(returning: outcome)
    }

    private func teardown() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        activeDrive?.cancel()
        activeDrive = nil
        driveFactory = nil
        panel?.orderOut(nil)
        panel = nil
    }
}
