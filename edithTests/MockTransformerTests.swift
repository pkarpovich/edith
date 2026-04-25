import Testing
@testable import edith

struct MockTransformerTests {
    @Test
    func emptyStringReturnsEmpty() {
        #expect(MockTransformer.transform("") == "")
    }

    @Test
    func asciiIsUppercased() {
        #expect(MockTransformer.transform("hello world") == "HELLO WORLD")
    }

    @Test
    func cyrillicIsUppercased() {
        #expect(MockTransformer.transform("привет мир") == "ПРИВЕТ МИР")
    }

    @Test
    func emojiAreLeftAlone() {
        #expect(MockTransformer.transform("hello 👋 world 🌍") == "HELLO 👋 WORLD 🌍")
    }

    @Test
    func mixedContentRetainsNonLetters() {
        #expect(MockTransformer.transform("Edith v0.1 - ready!") == "EDITH V0.1 - READY!")
    }
}
