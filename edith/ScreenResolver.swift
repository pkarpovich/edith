import AppKit
import ApplicationServices

@MainActor
enum ScreenResolver {
    static func activeScreen() -> NSScreen? {
        if let screen = screenFromFocusedWindow() {
            return screen
        }
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    static func centeredRect(for size: NSSize) -> NSRect {
        let frame = activeScreen()?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSRect(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
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
        let result = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { result.deallocate() }
        guard AXValueGetValue(value as! AXValue, type, result) else { return nil }
        return result.pointee
    }
}
