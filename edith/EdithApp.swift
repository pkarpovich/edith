import AppIntents
import AppKit
import os
import SwiftData
import SwiftUI

@main
struct EdithApp: App {
    @NSApplicationDelegateAdaptor(EdithAppDelegate.self) private var appDelegate

    private let container: ModelContainer

    init() {
        let container = Self.makeHistoryContainer()
        AppDependencyManager.shared.add(dependency: container)
        self.container = container
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
        } label: {
            Image(systemName: "sparkles")
        }
        .menuBarExtraStyle(.menu)
        .modelContainer(container)

        Settings {
            SettingsView()
        }
    }

    private static func makeHistoryContainer() -> ModelContainer {
        do {
            return try HistoryStore.makeContainer(at: HistoryStore.defaultURL)
        } catch {
            Logger.edith.error("History store unavailable, using in-memory store: \(error.localizedDescription, privacy: .public)")
        }
        do {
            return try HistoryStore.makeInMemoryContainer()
        } catch {
            fatalError("In-memory history store failed: \(error)")
        }
    }
}

private struct MenuBarContent: View {
    @State private var isAccessibilityGranted: Bool = PermissionsCheck.isAccessibilityGranted

    var body: some View {
        Text(PermissionsCheck.accessibilityStatusLabel(isGranted: isAccessibilityGranted))
        Button("Open Accessibility Settings...") {
            if let url = AccessibilityDeepLink.url {
                NSWorkspace.shared.open(url)
            }
        }
        Divider()
        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",")
        Divider()
        Button("Quit Edith") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

@MainActor
final class EdithAppDelegate: NSObject, NSApplicationDelegate {
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !PermissionsCheck.isAccessibilityGranted else { return }
        presentOnboardingWindow()
    }

    private func presentOnboardingWindow() {
        let hosting = NSHostingController(rootView: OnboardingView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Enable Accessibility"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }
}
