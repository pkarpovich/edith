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
    nonisolated func systemWideElement() -> AXUIElement
    nonisolated func copyAttributeValue(_ element: AXUIElement, attribute: String) -> Result<CFTypeRef, AXAttributeError>
}

nonisolated struct RealAXBackend: AXBackend {
    func systemWideElement() -> AXUIElement {
        AXUIElementCreateSystemWide()
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
}

nonisolated struct SelectionReader {
    private let backend: AXBackend

    init(backend: AXBackend = RealAXBackend()) {
        self.backend = backend
    }

    func readSelectedText() -> String? {
        let systemWide = backend.systemWideElement()

        guard case .success(let appValue) = backend.copyAttributeValue(systemWide, attribute: kAXFocusedApplicationAttribute as String) else {
            Logger.edith.info("SelectionReader: no focused application")
            return nil
        }
        guard CFGetTypeID(appValue) == AXUIElementGetTypeID() else {
            Logger.edith.info("SelectionReader: focused application has wrong type")
            return nil
        }
        let focusedApp = appValue as! AXUIElement

        guard case .success(let elementValue) = backend.copyAttributeValue(focusedApp, attribute: kAXFocusedUIElementAttribute as String) else {
            Logger.edith.info("SelectionReader: no focused UI element")
            return nil
        }
        guard CFGetTypeID(elementValue) == AXUIElementGetTypeID() else {
            Logger.edith.info("SelectionReader: focused UI element has wrong type")
            return nil
        }
        let focusedElement = elementValue as! AXUIElement

        guard case .success(let textValue) = backend.copyAttributeValue(focusedElement, attribute: kAXSelectedTextAttribute as String) else {
            Logger.edith.info("SelectionReader: no selected text attribute")
            return nil
        }
        guard let text = textValue as? String else {
            Logger.edith.info("SelectionReader: selected text has wrong type")
            return nil
        }
        guard !text.isEmpty else {
            Logger.edith.info("SelectionReader: selected text is empty")
            return nil
        }
        return text
    }
}
