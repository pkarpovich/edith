import AppKit
import ApplicationServices
import Foundation
import os

enum AXAttributeError: Error {
    case apiDisabled
    case noValue
    case attributeUnsupported
    case invalidUIElement
    case other(AXError)
}

protocol AXBackend {
    nonisolated func applicationElement(pid: pid_t) -> AXUIElement
    nonisolated func frontmostApplicationPID() -> pid_t?
    nonisolated func copyAttributeValue(_ element: AXUIElement, attribute: String) -> Result<CFTypeRef, AXAttributeError>
    nonisolated func copyParameterizedAttributeValue(_ element: AXUIElement, attribute: String, parameter: CFTypeRef) -> Result<CFTypeRef, AXAttributeError>
    nonisolated func setAttributeValue(_ element: AXUIElement, attribute: String, value: CFTypeRef)
}

nonisolated struct RealAXBackend: AXBackend {
    func applicationElement(pid: pid_t) -> AXUIElement {
        AXUIElementCreateApplication(pid)
    }

    func frontmostApplicationPID() -> pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    func copyAttributeValue(_ element: AXUIElement, attribute: String) -> Result<CFTypeRef, AXAttributeError> {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        switch error {
        case .success:
            guard let value else { return .failure(.noValue) }
            return .success(value)
        case .apiDisabled:
            return .failure(.apiDisabled)
        case .noValue:
            return .failure(.noValue)
        case .attributeUnsupported:
            return .failure(.attributeUnsupported)
        case .invalidUIElement:
            return .failure(.invalidUIElement)
        default:
            return .failure(.other(error))
        }
    }

    func copyParameterizedAttributeValue(_ element: AXUIElement, attribute: String, parameter: CFTypeRef) -> Result<CFTypeRef, AXAttributeError> {
        var value: CFTypeRef?
        let error = AXUIElementCopyParameterizedAttributeValue(element, attribute as CFString, parameter, &value)
        switch error {
        case .success:
            guard let value else { return .failure(.noValue) }
            return .success(value)
        case .apiDisabled:
            return .failure(.apiDisabled)
        case .noValue:
            return .failure(.noValue)
        case .attributeUnsupported:
            return .failure(.attributeUnsupported)
        case .invalidUIElement:
            return .failure(.invalidUIElement)
        default:
            return .failure(.other(error))
        }
    }

    func setAttributeValue(_ element: AXUIElement, attribute: String, value: CFTypeRef) {
        AXUIElementSetAttributeValue(element, attribute as CFString, value)
    }
}

nonisolated struct SelectionReader {
    private let backend: AXBackend
    private let retrySleepInterval: TimeInterval
    private let childWalkDepth: Int

    init(
        backend: AXBackend = RealAXBackend(),
        retrySleepInterval: TimeInterval = 0.08,
        childWalkDepth: Int = 2
    ) {
        self.backend = backend
        self.retrySleepInterval = retrySleepInterval
        self.childWalkDepth = childWalkDepth
    }

    func readSelectedText() -> String? {
        guard let pid = backend.frontmostApplicationPID() else {
            Logger.edith.info("SelectionReader: no frontmost application")
            return nil
        }

        let appElement = backend.applicationElement(pid: pid)

        // Chrome/Chromium and Electron disable their AX tree by default.
        // Setting these attributes wakes the tree so kAXSelectedTextAttribute starts working.
        backend.setAttributeValue(appElement, attribute: "AXEnhancedUserInterface", value: kCFBooleanTrue)
        backend.setAttributeValue(appElement, attribute: "AXManualAccessibility", value: kCFBooleanTrue)

        if let text = readFromApp(appElement) {
            return text
        }

        if retrySleepInterval > 0 {
            Thread.sleep(forTimeInterval: retrySleepInterval)
        }
        return readFromApp(appElement)
    }

    private func readFromApp(_ appElement: AXUIElement) -> String? {
        guard let focused = focusedElement(of: appElement) else {
            Logger.edith.info("SelectionReader: no focused UI element on app")
            return nil
        }

        if let text = selectedText(in: focused) {
            return text
        }

        if let text = childWithSelectedText(of: focused, depth: childWalkDepth) {
            Logger.edith.info("SelectionReader: found selection in nested child")
            return text
        }

        Logger.edith.info("SelectionReader: no selected text in focused subtree")
        return nil
    }

    private func focusedElement(of appElement: AXUIElement) -> AXUIElement? {
        guard case .success(let value) = backend.copyAttributeValue(appElement, attribute: kAXFocusedUIElementAttribute as String) else {
            return nil
        }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private func selectedText(in element: AXUIElement) -> String? {
        if let text = selectedTextAttribute(element) {
            return text
        }
        if let text = selectedTextViaValueAndRange(element) {
            return text
        }
        if let text = selectedTextViaMarkerRange(element) {
            return text
        }
        return nil
    }

    private func selectedTextAttribute(_ element: AXUIElement) -> String? {
        guard case .success(let value) = backend.copyAttributeValue(element, attribute: kAXSelectedTextAttribute as String) else {
            return nil
        }
        guard let text = value as? String, !text.isEmpty else {
            return nil
        }
        return text
    }

    private func selectedTextViaValueAndRange(_ element: AXUIElement) -> String? {
        guard case .success(let valueResult) = backend.copyAttributeValue(element, attribute: kAXValueAttribute as String),
              let fullText = valueResult as? String,
              !fullText.isEmpty else {
            return nil
        }
        guard case .success(let rangeResult) = backend.copyAttributeValue(element, attribute: kAXSelectedTextRangeAttribute as String) else {
            return nil
        }
        guard CFGetTypeID(rangeResult) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = rangeResult as! AXValue
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(axValue, .cfRange, &range), range.length > 0 else {
            return nil
        }
        let nsString = fullText as NSString
        guard range.location >= 0, range.location + range.length <= nsString.length else {
            return nil
        }
        return nsString.substring(with: NSRange(location: range.location, length: range.length))
    }

    // WebKit-native (Mail.app, Safari) uses opaque text markers instead of CFRange selections.
    // Read AXSelectedTextMarkerRange, then ask AXStringForTextMarkerRange to materialize the string.
    private func selectedTextViaMarkerRange(_ element: AXUIElement) -> String? {
        guard case .success(let markerRange) = backend.copyAttributeValue(element, attribute: "AXSelectedTextMarkerRange") else {
            return nil
        }
        guard case .success(let stringResult) = backend.copyParameterizedAttributeValue(
            element,
            attribute: "AXStringForTextMarkerRange",
            parameter: markerRange
        ) else {
            return nil
        }
        guard let text = stringResult as? String, !text.isEmpty else {
            return nil
        }
        Logger.edith.info("SelectionReader: matched via AXSelectedTextMarkerRange")
        return text
    }

    private func childWithSelectedText(of element: AXUIElement, depth: Int) -> String? {
        guard depth > 0 else { return nil }
        guard case .success(let value) = backend.copyAttributeValue(element, attribute: kAXChildrenAttribute as String) else {
            return nil
        }
        guard let array = value as? [AXUIElement], !array.isEmpty else {
            return nil
        }
        for child in array {
            if let text = selectedText(in: child) {
                return text
            }
            if let text = childWithSelectedText(of: child, depth: depth - 1) {
                return text
            }
        }
        return nil
    }
}
