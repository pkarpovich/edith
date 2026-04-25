import AppKit
import SwiftUI

@main
struct EdithApp: App {
    @NSApplicationDelegateAdaptor(EdithAppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
        } label: {
            Image(systemName: "sparkles")
        }
        .menuBarExtraStyle(.menu)
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
        Button("Quit edith") {
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
