import Foundation
import Testing
@testable import edith

struct PromptDefinitionParseTests {
    @Test
    func noFrontmatterReturnsContentAsBody() {
        let contents = "Hello world\n{{selection}}"
        let def = PromptDefinition.parse(contents: contents)
        #expect(def.model == nil)
        #expect(def.effort == nil)
        #expect(def.body == contents)
    }

    @Test
    func fullFrontmatterIsParsed() {
        let contents = """
        ---
        model: haiku
        effort: low
        ---
        Body line one
        Body line two
        """
        let def = PromptDefinition.parse(contents: contents)
        #expect(def.model == "haiku")
        #expect(def.effort == "low")
        #expect(def.body == "Body line one\nBody line two")
    }

    @Test
    func malformedYAMLFallsBackToNoFrontmatter() {
        let contents = """
        ---
        not a key value
        ---
        body
        """
        let def = PromptDefinition.parse(contents: contents)
        #expect(def.model == nil)
        #expect(def.effort == nil)
        #expect(def.body == contents)
    }

    @Test
    func missingClosingDelimiterFallsBack() {
        let contents = """
        ---
        model: haiku

        body without closing
        """
        let def = PromptDefinition.parse(contents: contents)
        #expect(def.model == nil)
        #expect(def.effort == nil)
        #expect(def.body == contents)
    }

    @Test
    func closingDelimiterNotOnItsOwnLineFallsBack() {
        let contents = """
        ---
        model: haiku
        --- extra
        body
        """
        let def = PromptDefinition.parse(contents: contents)
        #expect(def.model == nil)
        #expect(def.effort == nil)
        #expect(def.body == contents)
    }

    @Test
    func unknownFrontmatterKeysIgnored() {
        let contents = """
        ---
        model: haiku
        timeout: 30
        ---
        body
        """
        let def = PromptDefinition.parse(contents: contents)
        #expect(def.model == "haiku")
        #expect(def.effort == nil)
        #expect(def.body == "body")
    }

    @Test
    func crlfNormalized() {
        let contents = "---\r\nmodel: haiku\r\n---\r\nbody"
        let def = PromptDefinition.parse(contents: contents)
        #expect(def.model == "haiku")
        #expect(def.body == "body")
    }

    @Test
    func quotedFrontmatterValueStripped() {
        let contents = """
        ---
        model: "claude-haiku-4-5"
        effort: 'low'
        ---
        body
        """
        let def = PromptDefinition.parse(contents: contents)
        #expect(def.model == "claude-haiku-4-5")
        #expect(def.effort == "low")
    }

    @Test
    func emptyFrontmatterYieldsNilFields() {
        let contents = """
        ---
        ---
        body
        """
        let def = PromptDefinition.parse(contents: contents)
        #expect(def.model == nil)
        #expect(def.effort == nil)
        #expect(def.body == "body")
    }
}

struct PromptDefinitionCommentTests {
    @Test
    func multipleCommentLinesStripped() {
        let contents = """
        # First comment
        # Second comment
        # Third comment
        ---
        model: haiku
        ---
        body
        """
        let def = PromptDefinition.parse(contents: contents)
        #expect(def.model == "haiku")
        #expect(def.body == "body")
    }

    @Test
    func singleCommentLinePreserved() {
        let contents = """
        # Title
        body line
        """
        let def = PromptDefinition.parse(contents: contents)
        #expect(def.model == nil)
        #expect(def.body.contains("# Title"))
        #expect(def.body.contains("body line"))
    }

    @Test
    func blankLineStopsCommentStrip() {
        let contents = """
        # First

        # Second
        body
        """
        let def = PromptDefinition.parse(contents: contents)
        #expect(def.body == contents)
    }

    @Test
    func blankLineBetweenCommentsAndFrontmatterIsTolerated() {
        let contents = """
        # docs
        # vars

        ---
        model: haiku
        ---
        body
        """
        let def = PromptDefinition.parse(contents: contents)
        #expect(def.model == "haiku")
        #expect(def.body == "body")
    }
}

struct PromptDefinitionProviderTests {
    @Test
    func defaultsToCliWhenFrontmatterAbsent() {
        let def = PromptDefinition.parse(contents: "Hello {{selection}}")
        #expect(def.provider == .cli)
    }

    @Test
    func defaultsToCliWhenFrontmatterPresentWithoutProvider() {
        let contents = """
        ---
        model: haiku
        ---
        body
        """
        let def = PromptDefinition.parse(contents: contents)
        #expect(def.provider == .cli)
    }

    @Test
    func parsesCliExplicitly() {
        let contents = """
        ---
        provider: cli
        ---
        body
        """
        let def = PromptDefinition.parse(contents: contents)
        #expect(def.provider == .cli)
    }

    @Test
    func parsesApi() {
        let contents = """
        ---
        provider: api
        ---
        body
        """
        let def = PromptDefinition.parse(contents: contents)
        #expect(def.provider == .api)
    }

    @Test
    func unknownProviderFallsBackToCli() {
        let contents = """
        ---
        provider: bogus
        ---
        body
        """
        let def = PromptDefinition.parse(contents: contents)
        #expect(def.provider == .cli)
    }

    @Test
    func providerValueIsCaseInsensitive() {
        let contents = """
        ---
        provider: API
        ---
        body
        """
        let def = PromptDefinition.parse(contents: contents)
        #expect(def.provider == .api)
    }

    @Test
    func emptyProviderValueFallsBackToCli() {
        let contents = """
        ---
        provider:
        ---
        body
        """
        let def = PromptDefinition.parse(contents: contents)
        #expect(def.provider == .cli)
    }
}

struct PromptDefinitionNormalizeModelTests {
    @Test
    func extractsHaikuFromFullName() {
        #expect(PromptDefinition.normalizeModel("claude-haiku-4-5") == "haiku")
    }

    @Test
    func extractsSonnetFromFullName() {
        #expect(PromptDefinition.normalizeModel("claude-sonnet-4-6") == "sonnet")
    }

    @Test
    func extractsOpusFromFullName() {
        #expect(PromptDefinition.normalizeModel("claude-opus-4-7") == "opus")
    }

    @Test
    func keywordPassesThrough() {
        #expect(PromptDefinition.normalizeModel("haiku") == "haiku")
    }

    @Test
    func unknownModelPassesThrough() {
        #expect(PromptDefinition.normalizeModel("custom-model-x") == "custom-model-x")
    }

    @Test
    func caseInsensitiveMatch() {
        #expect(PromptDefinition.normalizeModel("CLAUDE-HAIKU-4") == "haiku")
    }
}

struct PromptDefinitionRenderTests {
    @Test
    func substitutesSelection() throws {
        let def = PromptDefinition(model: nil, effort: nil, provider: .cli, body: "Fix:\n\n{{selection}}")
        let result = try PromptDefinition.render(definition: def, variables: ["selection": "abc"])
        #expect(result == "Fix:\n\nabc")
    }

    @Test
    func missingSelectionAutoAppended() throws {
        let def = PromptDefinition(model: nil, effort: nil, provider: .cli, body: "Fix the text")
        let result = try PromptDefinition.render(definition: def, variables: ["selection": "abc"])
        #expect(result == "Fix the text\n\nabc")
    }

    @Test
    func unknownPlaceholderThrows() {
        let def = PromptDefinition(model: nil, effort: nil, provider: .cli, body: "Fix {{nonsense}} {{selection}}")
        #expect(throws: PromptParserError.unknownVariable(name: "nonsense")) {
            _ = try PromptDefinition.render(definition: def, variables: ["selection": "abc"])
        }
    }

    @Test
    func multipleSelectionOccurrencesReplaced() throws {
        let def = PromptDefinition(model: nil, effort: nil, provider: .cli, body: "{{selection}}\n---\n{{selection}}")
        let result = try PromptDefinition.render(definition: def, variables: ["selection": "x"])
        #expect(result == "x\n---\nx")
    }

    @Test
    func selectionContainingPlaceholderSyntaxIsNotMisreadAsUnknownVariable() throws {
        let def = PromptDefinition(model: nil, effort: nil, provider: .cli, body: "Fix:\n{{selection}}")
        let result = try PromptDefinition.render(
            definition: def,
            variables: ["selection": "use {{name}} in templates"]
        )
        #expect(result == "Fix:\nuse {{name}} in templates")
    }

    @Test
    func spacedPlaceholderIsRejectedAsUnknown() {
        let def = PromptDefinition(model: nil, effort: nil, provider: .cli, body: "Fix:\n{{ selection }}")
        #expect(throws: (any Error).self) {
            _ = try PromptDefinition.render(definition: def, variables: ["selection": "abc"])
        }
    }
}
