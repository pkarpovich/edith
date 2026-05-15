import SwiftUI

struct OverlayView: View {
    let model: OverlayStateModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Palette.separator(colorScheme))
            bodySection
            Divider().background(Palette.separator(colorScheme))
            footer
        }
        .frame(width: DesignTokens.Window.width)
        .background(
            Palette.windowBackground(colorScheme)
                .background(.regularMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Window.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Window.radius, style: .continuous)
                .strokeBorder(Palette.windowStroke(colorScheme), lineWidth: 0.5)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Palette.windowInnerStrokeTop(colorScheme))
                .frame(height: 0.5)
                .padding(.horizontal, 0.5)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            brandMark
            Text("Edith")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.textPrimary(colorScheme))
                .tracking(0.1)
            if let promptName = model.promptName {
                Text(promptName)
                    .font(.system(size: DesignTokens.Chip.fontSize, design: .monospaced))
                    .foregroundStyle(Palette.textSecondary(colorScheme))
                    .padding(.horizontal, DesignTokens.Chip.horizontalPadding)
                    .padding(.vertical, DesignTokens.Chip.verticalPadding)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Chip.radius, style: .continuous)
                            .fill(Palette.fillSubtle(colorScheme))
                    )
            }
            Spacer(minLength: 8)
            stateActivity
        }
        .padding(.horizontal, DesignTokens.Header.horizontalPadding)
        .padding(.top, DesignTokens.Header.topPadding)
        .padding(.bottom, DesignTokens.Header.bottomPadding)
    }

    private var brandMark: some View {
        RoundedRectangle(cornerRadius: DesignTokens.Header.markRadius, style: .continuous)
            .fill(Palette.brandMarkGradient)
            .frame(width: DesignTokens.Header.markSize, height: DesignTokens.Header.markSize)
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Header.markRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.5)
                    .blendMode(.overlay)
            )
    }

    @ViewBuilder
    private var stateActivity: some View {
        switch model.state {
        case .processing:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.8)
                Text("Thinking…")
            }
            .font(.system(size: 11))
            .foregroundStyle(Palette.textSecondary(colorScheme))
        case .streaming:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.8)
                Text("Writing…")
            }
            .font(.system(size: 11))
            .foregroundStyle(Palette.textSecondary(colorScheme))
        case .ready:
            HStack(spacing: 6) {
                Circle()
                    .fill(Palette.accentGreen(colorScheme))
                    .frame(width: 6, height: 6)
                Text("Ready")
            }
            .font(.system(size: 11))
            .foregroundStyle(Palette.textSecondary(colorScheme))
        case .error:
            HStack(spacing: 6) {
                Circle()
                    .fill(Palette.error(colorScheme))
                    .frame(width: 6, height: 6)
                Text("Error")
            }
            .font(.system(size: 11))
            .foregroundStyle(Palette.textSecondary(colorScheme))
        }
    }

    private var bodySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            bodyContent
        }
        .padding(.horizontal, DesignTokens.Body.horizontalPadding)
        .padding(.vertical, DesignTokens.Body.verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var bodyContent: some View {
        switch model.state {
        case .processing(let original):
            sourceText(original)
        case .streaming(_, let partial):
            Text(partial)
                .font(.system(size: DesignTokens.Body.bodyFontSize))
                .foregroundStyle(Palette.textPrimary(colorScheme))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(maxHeight: DesignTokens.Body.maxHeight)
        case .ready(let original, let result):
            readyBody(original: original, result: result)
        case .error(let original, let message):
            VStack(alignment: .leading, spacing: 10) {
                sourceText(original)
                errorBlock(message: message)
            }
        }
    }

    private func sourceText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: DesignTokens.Body.bodyFontSize))
            .foregroundStyle(Palette.textSecondary(colorScheme))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func readyBody(original: String, result: String) -> some View {
        if original == result {
            Text("Текст уже корректен - изменений не нужно.")
                .font(.system(size: DesignTokens.Body.bodyFontSize, weight: .regular).italic())
                .foregroundStyle(Palette.textSecondary(colorScheme))
        } else {
            ScrollView {
                Text(
                    attributedDiff(
                        original: original,
                        result: result,
                        insertColor: Palette.accentGreenSoft(colorScheme),
                        insertForeground: Palette.accentGreenLabel(colorScheme)
                    )
                )
                .font(.system(size: DesignTokens.Body.bodyFontSize))
                .foregroundStyle(Palette.textPrimary(colorScheme))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: DesignTokens.Body.maxHeight)
        }
    }

    private func errorBlock(message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("!")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.errorLabel(colorScheme))
            VStack(alignment: .leading, spacing: 2) {
                Text("Не удалось получить ответ")
                    .font(.system(size: 12, weight: .semibold))
                Text(message)
                    .font(.system(size: 12))
                    .opacity(0.85)
            }
        }
        .foregroundStyle(Palette.errorLabel(colorScheme))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Palette.errorBackground(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Palette.errorBorder(colorScheme), lineWidth: 0.5)
        )
    }

    private var footer: some View {
        HStack(spacing: 12) {
            footerKeycaps
            Spacer(minLength: 8)
            footerMeta
        }
        .font(.system(size: DesignTokens.Footer.fontSize))
        .foregroundStyle(Palette.textSecondary(colorScheme))
        .padding(.horizontal, DesignTokens.Footer.horizontalPadding)
        .padding(.top, DesignTokens.Footer.topPadding)
        .padding(.bottom, DesignTokens.Footer.bottomPadding)
        .background(Palette.footerBackground(colorScheme))
    }

    @ViewBuilder
    private var footerKeycaps: some View {
        switch model.state {
        case .ready:
            HStack(spacing: 12) {
                keycapWithLabel("⏎", label: "apply", accent: true)
                keycapWithLabel("esc", label: "cancel", accent: false)
            }
        case .error:
            HStack(spacing: 12) {
                keycapWithLabel("esc", label: "dismiss", accent: false)
                keycapWithLabel("⌘R", label: "retry", accent: false)
            }
        case .processing, .streaming:
            keycapWithLabel("esc", label: "cancel", accent: false)
        }
    }

    @ViewBuilder
    private var footerMeta: some View {
        switch model.state {
        case .ready(let original, let result):
            let delta = abs(result.count - original.count)
            Text("\(delta) char · 1 edit")
                .opacity(0.7)
        case .processing, .streaming:
            if let label = model.modelLabel {
                Text(label).opacity(0.7)
            }
        case .error:
            EmptyView()
        }
    }

    private func keycapWithLabel(_ glyph: String, label: String, accent: Bool) -> some View {
        HStack(spacing: 6) {
            keycap(glyph, accent: accent)
            Text(label)
        }
    }

    private func keycap(_ glyph: String, accent: Bool) -> some View {
        Text(glyph)
            .font(.system(size: DesignTokens.Keycap.fontSize, weight: .medium, design: .monospaced))
            .foregroundStyle(
                accent
                    ? Palette.accentGreenLabel(colorScheme)
                    : Palette.textSecondary(colorScheme)
            )
            .padding(.horizontal, DesignTokens.Keycap.horizontalPadding)
            .frame(minWidth: DesignTokens.Keycap.minWidth, minHeight: DesignTokens.Keycap.height)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Keycap.radius, style: .continuous)
                    .fill(
                        accent
                            ? Palette.accentGreenKeycapBg(colorScheme)
                            : Palette.fillSubtle(colorScheme)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Keycap.radius, style: .continuous)
                    .strokeBorder(
                        accent
                            ? Palette.accentGreenKeycapStroke(colorScheme)
                            : Palette.separator(colorScheme),
                        lineWidth: 0.5
                    )
            )
    }
}
