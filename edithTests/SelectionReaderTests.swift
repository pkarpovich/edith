import ApplicationServices
import Testing
@testable import edith

struct SelectionReaderTests {
    @Test
    func noFrontmostAppReturnsNil() {
        let backend = FakeAXBackend(pid: nil)
        let reader = SelectionReader(backend: backend, retrySleepInterval: 0)
        #expect(reader.readSelectedText() == nil)
    }

    @Test
    func missingFocusedElementReturnsNil() {
        let backend = FakeAXBackend(pid: 100) { _, _ in .failure(.noValue) }
        let reader = SelectionReader(backend: backend, retrySleepInterval: 0)
        #expect(reader.readSelectedText() == nil)
    }

    @Test
    func apiDisabledReturnsNil() {
        let backend = FakeAXBackend(pid: 100) { _, _ in .failure(.apiDisabled) }
        let reader = SelectionReader(backend: backend, retrySleepInterval: 0)
        #expect(reader.readSelectedText() == nil)
    }

    @Test
    func missingSelectedTextOnFocusedAndNoChildrenReturnsNil() {
        let dummy = AXUIElementCreateSystemWide()
        let backend = FakeAXBackend(pid: 100) { _, attribute in
            switch attribute {
            case kAXFocusedUIElementAttribute as String:
                return .success(dummy)
            case kAXSelectedTextAttribute as String:
                return .failure(.attributeUnsupported)
            case kAXChildrenAttribute as String:
                return .failure(.noValue)
            default:
                return .failure(.noValue)
            }
        }
        let reader = SelectionReader(backend: backend, retrySleepInterval: 0)
        #expect(reader.readSelectedText() == nil)
    }

    @Test
    func wrongTypeForSelectedTextReturnsNil() {
        let dummy = AXUIElementCreateSystemWide()
        let backend = FakeAXBackend(pid: 100) { _, attribute in
            switch attribute {
            case kAXFocusedUIElementAttribute as String:
                return .success(dummy)
            case kAXSelectedTextAttribute as String:
                return .success(NSNumber(value: 42) as CFTypeRef)
            case kAXChildrenAttribute as String:
                return .failure(.noValue)
            default:
                return .failure(.noValue)
            }
        }
        let reader = SelectionReader(backend: backend, retrySleepInterval: 0)
        #expect(reader.readSelectedText() == nil)
    }

    @Test
    func emptySelectionReturnsNil() {
        let dummy = AXUIElementCreateSystemWide()
        let backend = FakeAXBackend(pid: 100) { _, attribute in
            switch attribute {
            case kAXFocusedUIElementAttribute as String:
                return .success(dummy)
            case kAXSelectedTextAttribute as String:
                return .success("" as CFString)
            case kAXChildrenAttribute as String:
                return .failure(.noValue)
            default:
                return .failure(.noValue)
            }
        }
        let reader = SelectionReader(backend: backend, retrySleepInterval: 0)
        #expect(reader.readSelectedText() == nil)
    }

    @Test
    func validSelectionOnFocusedReturnsString() {
        let dummy = AXUIElementCreateSystemWide()
        let backend = FakeAXBackend(pid: 100) { _, attribute in
            switch attribute {
            case kAXFocusedUIElementAttribute as String:
                return .success(dummy)
            case kAXSelectedTextAttribute as String:
                return .success("hello world" as CFString)
            default:
                return .failure(.noValue)
            }
        }
        let reader = SelectionReader(backend: backend, retrySleepInterval: 0)
        #expect(reader.readSelectedText() == "hello world")
    }

    @Test
    func selectionFoundInChildElement() {
        let appElement = AXUIElementCreateApplication(100)
        let focused = AXUIElementCreateApplication(101)
        let child = AXUIElementCreateApplication(102)

        let backend = FakeAXBackend(
            pid: 100,
            appElementOverride: appElement
        ) { element, attribute in
            if attribute == kAXFocusedUIElementAttribute as String, CFEqual(element, appElement) {
                return .success(focused)
            }
            if attribute == kAXSelectedTextAttribute as String, CFEqual(element, focused) {
                return .failure(.attributeUnsupported)
            }
            if attribute == kAXChildrenAttribute as String, CFEqual(element, focused) {
                return .success([child] as CFArray)
            }
            if attribute == kAXSelectedTextAttribute as String, CFEqual(element, child) {
                return .success("nested selection" as CFString)
            }
            return .failure(.noValue)
        }
        let reader = SelectionReader(backend: backend, retrySleepInterval: 0)
        #expect(reader.readSelectedText() == "nested selection")
    }
}

nonisolated struct FakeAXBackend: AXBackend {
    let pid: pid_t?
    let appElementOverride: AXUIElement?
    let onCopy: (AXUIElement, String) -> Result<CFTypeRef, AXAttributeError>

    init(
        pid: pid_t?,
        appElementOverride: AXUIElement? = nil,
        onCopy: @escaping (AXUIElement, String) -> Result<CFTypeRef, AXAttributeError> = { _, _ in .failure(.noValue) }
    ) {
        self.pid = pid
        self.appElementOverride = appElementOverride
        self.onCopy = onCopy
    }

    func applicationElement(pid: pid_t) -> AXUIElement {
        appElementOverride ?? AXUIElementCreateApplication(pid)
    }

    func frontmostApplicationPID() -> pid_t? {
        pid
    }

    func copyAttributeValue(_ element: AXUIElement, attribute: String) -> Result<CFTypeRef, AXAttributeError> {
        onCopy(element, attribute)
    }

    func copyParameterizedAttributeValue(_ element: AXUIElement, attribute: String, parameter: CFTypeRef) -> Result<CFTypeRef, AXAttributeError> {
        .failure(.noValue)
    }

    func setAttributeValue(_ element: AXUIElement, attribute: String, value: CFTypeRef) {
        // no-op in tests
    }
}
