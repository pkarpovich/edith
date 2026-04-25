import AppKit
import ApplicationServices
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

    init(initial: OverlayState) {
        self.model = OverlayStateModel(initial: initial)
    }

    func present() async -> Outcome {
        await withCheckedContinuation { continuation in
            self.continuation = continuation

            let hosting = NSHostingView(rootView: OverlayView(model: model))
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
                    self.confirm()
                    return nil
                case 53:
                    self.dismiss()
                    return nil
                default:
                    return event
                }
            }

            panel.makeKeyAndOrderFront(nil)
        }
    }

    @discardableResult
    func confirm() -> Bool {
        guard case .ready(_, let result) = model.state else { return false }
        resolve(.confirmed(result))
        return true
    }

    func dismiss() {
        resolve(.dismissed)
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
        panel?.orderOut(nil)
        panel = nil
    }

    private static func centeredRect(for size: NSSize) -> NSRect {
        let screen = activeScreen()
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = frame.midX - size.width / 2
        let y = frame.midY - size.height / 2
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private static func activeScreen() -> NSScreen? {
        if let screen = screenFromFocusedWindow() {
            return screen
        }
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    private static func screenFromFocusedWindow() -> NSScreen? {
        guard let frame = focusedWindowAXFrame(), let primary = NSScreen.screens.first else {
            return nil
        }
        let axCenter = CGPoint(x: frame.midX, y: frame.midY)
        let nsCenter = CGPoint(x: axCenter.x, y: primary.frame.maxY - axCenter.y)
        return NSScreen.screens.first { NSMouseInRect(nsCenter, $0.frame, false) }
    }

    private static func focusedWindowAXFrame() -> CGRect? {
        let systemWide = AXUIElementCreateSystemWide()
        guard let app = copyAXElement(systemWide, attribute: kAXFocusedApplicationAttribute) else {
            return nil
        }
        guard let window = copyAXElement(app, attribute: kAXFocusedWindowAttribute) else {
            return nil
        }
        guard
            let position: CGPoint = copyAXValue(window, attribute: kAXPositionAttribute, type: .cgPoint),
            let size: CGSize = copyAXValue(window, attribute: kAXSizeAttribute, type: .cgSize)
        else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private static func copyAXElement(_ element: AXUIElement, attribute: String) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let value = ref,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private static func copyAXValue<T>(_ element: AXUIElement, attribute: String, type: AXValueType) -> T? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let value = ref,
              CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }
        var result = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { result.deallocate() }
        guard AXValueGetValue(value as! AXValue, type, result) else { return nil }
        return result.pointee
    }
}
