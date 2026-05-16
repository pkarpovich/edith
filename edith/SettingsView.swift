import SwiftUI

enum SettingsStatus: Equatable {
    case unknown
    case keySaved
    case noKey
    case empty
    case error(String)

    var label: String {
        switch self {
        case .unknown: return " "
        case .keySaved: return "key saved"
        case .noKey: return "no key"
        case .empty: return "enter a key"
        case .error(let message): return "error: \(message)"
        }
    }
}

@MainActor
@Observable
final class SettingsModel {
    var keyInput: String = ""
    var isRevealed: Bool = false
    private(set) var status: SettingsStatus = .unknown

    @ObservationIgnored private let store: KeychainStore

    init(store: KeychainStore = KeychainStore()) {
        self.store = store
    }

    func refreshStatus() {
        if let key = store.read(), !key.isEmpty {
            status = .keySaved
        } else {
            status = .noKey
        }
    }

    func save() {
        let trimmed = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            status = .empty
            return
        }
        do {
            try store.write(trimmed)
            keyInput = ""
            status = .keySaved
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    func clear() {
        do {
            try store.delete()
            keyInput = ""
            status = .noKey
        } catch {
            status = .error(error.localizedDescription)
        }
    }
}

struct SettingsView: View {
    @State private var model: SettingsModel

    init(model: SettingsModel = SettingsModel()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                HStack {
                    Group {
                        if model.isRevealed {
                            TextField("sk-ant-…", text: $model.keyInput)
                        } else {
                            SecureField("sk-ant-…", text: $model.keyInput)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    Button(model.isRevealed ? "Hide" : "Show") {
                        model.isRevealed.toggle()
                    }
                }
            } header: {
                Text("Anthropic API Key")
            } footer: {
                Text(model.status.label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Save") {
                    model.save()
                }
                .keyboardShortcut(.defaultAction)
                Button("Clear", role: .destructive) {
                    model.clear()
                }
                Spacer()
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(minWidth: 460, minHeight: 220)
        .onAppear {
            model.refreshStatus()
        }
    }
}
