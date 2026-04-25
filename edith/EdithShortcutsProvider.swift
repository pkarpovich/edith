import AppIntents

struct EdithShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskEdithIntent(),
            phrases: [
                "Ask \(.applicationName)"
            ],
            shortTitle: "Ask Edith",
            systemImageName: "sparkles"
        )
    }
}
