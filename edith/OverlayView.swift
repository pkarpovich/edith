import SwiftUI

struct OverlayView: View {
    let model: OverlayStateModel

    var body: some View {
        VStack(spacing: 0) {
            OverlayHeader(model: model)
            Divider()
            OverlayBody(model: model)
            Divider()
            OverlayFooter(model: model)
        }
        .frame(width: DesignTokens.Window.width)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Window.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Window.radius, style: .continuous)
                .strokeBorder(.primary.opacity(0.10), lineWidth: 0.5)
        )
    }
}

private struct OverlayHeader: View {
    let model: OverlayStateModel

    var body: some View {
        HStack(spacing: 8) {
            BrandMark()
            Text("Edith")
                .font(.callout)
                .fontWeight(.semibold)
                .tracking(0.1)
            if let promptName = model.promptName {
                PromptChip(name: promptName)
            }
            Spacer(minLength: 8)
            StateActivity(state: model.state)
        }
        .padding(.horizontal, DesignTokens.Header.horizontalPadding)
        .padding(.top, DesignTokens.Header.topPadding)
        .padding(.bottom, DesignTokens.Header.bottomPadding)
    }
}

private struct BrandMark: View {
    var body: some View {
        RoundedRectangle(cornerRadius: DesignTokens.Header.markRadius, style: .continuous)
            .fill(Brand.markGradient)
            .frame(width: DesignTokens.Header.markSize, height: DesignTokens.Header.markSize)
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Header.markRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.5)
                    .blendMode(.overlay)
            )
    }
}

private struct PromptChip: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .padding(.horizontal, DesignTokens.Chip.horizontalPadding)
            .padding(.vertical, DesignTokens.Chip.verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Chip.radius, style: .continuous)
                    .fill(.quaternary)
            )
    }
}

private struct StateActivity: View {
    let state: OverlayState

    var body: some View {
        HStack(spacing: 6) {
            icon
            Text(label)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder private var icon: some View {
        switch state {
        case .processing, .streaming:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.8)
        case .ready:
            Circle().fill(.green).frame(width: 6, height: 6)
        case .error:
            Circle().fill(.red).frame(width: 6, height: 6)
        }
    }

    private var label: String {
        switch state {
        case .processing: return "Thinking…"
        case .streaming: return "Writing…"
        case .ready: return "Ready"
        case .error: return "Error"
        }
    }
}

private struct OverlayBody: View {
    let model: OverlayStateModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.horizontal, DesignTokens.Body.horizontalPadding)
        .padding(.vertical, DesignTokens.Body.verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .processing(let original):
            SourceText(original)
        case .streaming(_, let partial):
            Text(partial)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(maxHeight: DesignTokens.Body.maxHeight)
        case .ready(let original, let result):
            ReadyBody(original: original, result: result)
        case .error(let original, let message):
            VStack(alignment: .leading, spacing: 10) {
                SourceText(original)
                ErrorBlock(message: message)
            }
        }
    }
}

private struct SourceText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ReadyBody: View {
    let original: String
    let result: String

    var body: some View {
        if original == result {
            Text("Текст уже корректен - изменений не нужно.")
                .font(.body.italic())
                .foregroundStyle(.secondary)
        } else {
            ScrollView {
                Text(
                    attributedDiff(
                        original: original,
                        result: result,
                        insertColor: .edithDiffBackground,
                        insertForeground: .edithDiffForeground
                    )
                )
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: DesignTokens.Body.maxHeight)
        }
    }
}

private struct ErrorBlock: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("!")
                .font(.body.weight(.semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text("Не удалось получить ответ")
                    .font(.callout.weight(.semibold))
                Text(message)
                    .font(.callout)
                    .opacity(0.85)
            }
        }
        .foregroundStyle(Color.edithErrorLabel)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.edithErrorBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.edithErrorBorder, lineWidth: 0.5)
        )
    }
}

private struct OverlayFooter: View {
    let model: OverlayStateModel

    var body: some View {
        HStack(spacing: 12) {
            keycaps
            Spacer(minLength: 8)
            meta
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, DesignTokens.Footer.horizontalPadding)
        .padding(.top, DesignTokens.Footer.topPadding)
        .padding(.bottom, DesignTokens.Footer.bottomPadding)
        .background(.quinary)
    }

    @ViewBuilder private var keycaps: some View {
        switch model.state {
        case .ready:
            HStack(spacing: 12) {
                KeycapHint(glyph: "⏎", label: "apply", accent: true)
                KeycapHint(glyph: "esc", label: "cancel")
            }
        case .error:
            HStack(spacing: 12) {
                KeycapHint(glyph: "esc", label: "dismiss")
                KeycapHint(glyph: "⌘R", label: "retry")
            }
        case .processing, .streaming:
            KeycapHint(glyph: "esc", label: "cancel")
        }
    }

    @ViewBuilder private var meta: some View {
        switch model.state {
        case .ready(let original, let result):
            let delta = abs(result.count - original.count)
            Text("\(delta) char · 1 edit").opacity(0.7)
        case .processing, .streaming:
            if let label = model.modelLabel {
                Text(label).opacity(0.7)
            }
        case .error:
            EmptyView()
        }
    }
}

private struct KeycapHint: View {
    let glyph: String
    let label: String
    var accent: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Keycap(glyph: glyph, accent: accent)
            Text(label)
        }
    }
}

private struct Keycap: View {
    let glyph: String
    let accent: Bool

    var body: some View {
        Text(glyph)
            .font(.system(size: DesignTokens.Keycap.fontSize, weight: .medium, design: .monospaced))
            .foregroundStyle(accent ? Color.edithDiffForeground : .secondary)
            .padding(.horizontal, DesignTokens.Keycap.horizontalPadding)
            .frame(minWidth: DesignTokens.Keycap.minWidth, minHeight: DesignTokens.Keycap.height)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Keycap.radius, style: .continuous)
                    .fill(accent ? AnyShapeStyle(Color.edithAccentKeycapBackground) : AnyShapeStyle(.quaternary))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Keycap.radius, style: .continuous)
                    .strokeBorder(
                        accent ? AnyShapeStyle(Color.edithAccentKeycapStroke) : AnyShapeStyle(.separator),
                        lineWidth: 0.5
                    )
            )
    }
}
