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
final class SettingsModel: ObservableObject {
    @Published var keyInput: String = ""
    @Published var isRevealed: Bool = false
    @Published private(set) var status: SettingsStatus = .unknown

    private let store: KeychainStore

    init(store: KeychainStore = KeychainStore()) {
        self.store = store
    }

    func refreshStatus() {
        status = store.read() == nil ? .noKey : .keySaved
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
            status = .error(String(describing: error))
        }
    }

    func clear() {
        do {
            try store.delete()
            keyInput = ""
            status = .noKey
        } catch {
            status = .error(String(describing: error))
        }
    }
}

struct SettingsView: View {
    @StateObject private var model: SettingsModel

    init(model: SettingsModel = SettingsModel()) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
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
