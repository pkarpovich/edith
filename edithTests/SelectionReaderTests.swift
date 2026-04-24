import ApplicationServices
import Testing
@testable import edith

struct SelectionReaderTests {
    @Test
    func apiDisabledReturnsNil() {
        let backend = FakeAXBackend { _ in .failure(.apiDisabled) }
        let reader = SelectionReader(backend: backend)
        #expect(reader.readSelectedText() == nil)
    }

    @Test
    func missingFocusedAppReturnsNil() {
        let backend = FakeAXBackend { attribute in
            switch attribute {
            case kAXFocusedApplicationAttribute as String:
                return .failure(.noValue)
            default:
                return .failure(.attributeUnsupported)
            }
        }
        let reader = SelectionReader(backend: backend)
        #expect(reader.readSelectedText() == nil)
    }

    @Test
    func missingSelectedTextReturnsNil() {
        let dummyElement = AXUIElementCreateSystemWide()
        let backend = FakeAXBackend { attribute in
            switch attribute {
            case kAXFocusedApplicationAttribute as String, kAXFocusedUIElementAttribute as String:
                return .success(dummyElement)
            case kAXSelectedTextAttribute as String:
                return .failure(.attributeUnsupported)
            default:
                return .failure(.noValue)
            }
        }
        let reader = SelectionReader(backend: backend)
        #expect(reader.readSelectedText() == nil)
    }

    @Test
    func wrongTypeForSelectedTextReturnsNil() {
        let dummyElement = AXUIElementCreateSystemWide()
        let backend = FakeAXBackend { attribute in
            switch attribute {
            case kAXFocusedApplicationAttribute as String, kAXFocusedUIElementAttribute as String:
                return .success(dummyElement)
            case kAXSelectedTextAttribute as String:
                return .success(NSNumber(value: 42) as CFTypeRef)
            default:
                return .failure(.noValue)
            }
        }
        let reader = SelectionReader(backend: backend)
        #expect(reader.readSelectedText() == nil)
    }

    @Test
    func emptySelectionReturnsNil() {
        let dummyElement = AXUIElementCreateSystemWide()
        let backend = FakeAXBackend { attribute in
            switch attribute {
            case kAXFocusedApplicationAttribute as String, kAXFocusedUIElementAttribute as String:
                return .success(dummyElement)
            case kAXSelectedTextAttribute as String:
                return .success("" as CFString)
            default:
                return .failure(.noValue)
            }
        }
        let reader = SelectionReader(backend: backend)
        #expect(reader.readSelectedText() == nil)
    }

    @Test
    func validSelectionReturnsString() {
        let dummyElement = AXUIElementCreateSystemWide()
        let backend = FakeAXBackend { attribute in
            switch attribute {
            case kAXFocusedApplicationAttribute as String, kAXFocusedUIElementAttribute as String:
                return .success(dummyElement)
            case kAXSelectedTextAttribute as String:
                return .success("hello world" as CFString)
            default:
                return .failure(.noValue)
            }
        }
        let reader = SelectionReader(backend: backend)
        #expect(reader.readSelectedText() == "hello world")
    }
}

nonisolated struct FakeAXBackend: AXBackend {
    let onCopy: (String) -> Result<CFTypeRef, AXAttributeError>

    func systemWideElement() -> AXUIElement {
        AXUIElementCreateSystemWide()
    }

    func copyAttributeValue(_ element: AXUIElement, attribute: String) -> Result<CFTypeRef, AXAttributeError> {
        onCopy(attribute)
    }
}
