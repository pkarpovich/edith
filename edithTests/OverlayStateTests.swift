import Testing
@testable import edith

struct OverlayStateTests {
    @Test
    func originalAccessibleInProcessing() {
        let state: OverlayState = .processing(original: "hi")
        #expect(state.original == "hi")
    }

    @Test
    func originalAccessibleInReady() {
        let state: OverlayState = .ready(original: "hi", result: "HI")
        #expect(state.original == "hi")
    }

    @Test
    func originalAccessibleInError() {
        let state: OverlayState = .error(original: "hi", message: "boom")
        #expect(state.original == "hi")
    }

    @Test
    func originalAccessibleInStreaming() {
        let state: OverlayState = .streaming(original: "hi", partial: "H")
        #expect(state.original == "hi")
    }

    @Test
    func equalityHonorsAssociatedValues() {
        #expect(OverlayState.processing(original: "a") == .processing(original: "a"))
        #expect(OverlayState.processing(original: "a") != .processing(original: "b"))
        #expect(OverlayState.ready(original: "a", result: "A") == .ready(original: "a", result: "A"))
        #expect(OverlayState.ready(original: "a", result: "A") != .ready(original: "a", result: "B"))
        #expect(OverlayState.error(original: "a", message: "m") == .error(original: "a", message: "m"))
        #expect(OverlayState.processing(original: "a") != .ready(original: "a", result: "A"))
        #expect(OverlayState.streaming(original: "a", partial: "x") == .streaming(original: "a", partial: "x"))
        #expect(OverlayState.streaming(original: "a", partial: "x") != .streaming(original: "a", partial: "y"))
        #expect(OverlayState.streaming(original: "a", partial: "x") != .streaming(original: "b", partial: "x"))
        #expect(OverlayState.streaming(original: "a", partial: "x") != .processing(original: "a"))
        #expect(OverlayState.streaming(original: "a", partial: "x") != .ready(original: "a", result: "x"))
    }
}

@MainActor
struct OverlayStateModelTests {
    @Test
    func initialStateIsRetained() {
        let model = OverlayStateModel(initial: .processing(original: "hello"))
        #expect(model.state == .processing(original: "hello"))
    }

    @Test
    func transitionFromProcessingToReady() {
        let model = OverlayStateModel(initial: .processing(original: "hello"))
        model.state = .ready(original: "hello", result: "HELLO")
        #expect(model.state == .ready(original: "hello", result: "HELLO"))
    }

    @Test
    func transitionFromProcessingToError() {
        let model = OverlayStateModel(initial: .processing(original: "hello"))
        model.state = .error(original: "hello", message: "claude not found")
        #expect(model.state == .error(original: "hello", message: "claude not found"))
    }

    @Test
    func transitionPreservesOriginal() {
        let model = OverlayStateModel(initial: .processing(original: "keep me"))
        model.state = .ready(original: "keep me", result: "KEEP ME")
        #expect(model.state.original == "keep me")
        model.state = .error(original: "keep me", message: "x")
        #expect(model.state.original == "keep me")
    }

    @Test
    func transitionFromProcessingToStreamingAndReady() {
        let model = OverlayStateModel(initial: .processing(original: "hi"))
        model.state = .streaming(original: "hi", partial: "H")
        #expect(model.state == .streaming(original: "hi", partial: "H"))
        model.state = .streaming(original: "hi", partial: "HI")
        #expect(model.state == .streaming(original: "hi", partial: "HI"))
        #expect(model.state.original == "hi")
        model.state = .ready(original: "hi", result: "HI")
        #expect(model.state == .ready(original: "hi", result: "HI"))
    }
}
