import SwiftUI

struct OverlayView: View {
    let model: OverlayStateModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
            Divider()
            HStack(spacing: 20) {
                hints
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 640)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .ready(let original, let result):
            inlineDiffColumn(original: original, result: result)
        default:
            HStack(alignment: .top, spacing: 16) {
                column(title: "Original", body: model.state.original)
                rightColumn
            }
        }
    }

    private func inlineDiffColumn(original: String, result: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Result")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(attributedDiff(original: original, result: result, insertColor: Color.green.opacity(0.25)))
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 240)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var rightColumn: some View {
        switch model.state {
        case .ready:
            EmptyView()
        case .processing:
            VStack(alignment: .leading, spacing: 6) {
                Text("Result")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("thinking…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: 200, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .streaming(_, let partial):
            VStack(alignment: .leading, spacing: 6) {
                Text("Result")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                ScrollView {
                    Text(partial)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("streaming…")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .error(_, let message):
            VStack(alignment: .leading, spacing: 6) {
                Text("Error")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.red)
                ScrollView {
                    Text(message)
                        .font(.body)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var hints: some View {
        switch model.state {
        case .processing:
            hint(label: "Cancel", symbol: "escape")
        case .streaming:
            hint(label: "Cancel", symbol: "escape")
        case .ready:
            hint(label: "Apply", symbol: "return")
            hint(label: "Cancel", symbol: "escape")
        case .error:
            hint(label: "Dismiss", symbol: "escape")
        }
    }

    private func column(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(body)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hint(label: String, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            Text(label)
        }
    }
}
