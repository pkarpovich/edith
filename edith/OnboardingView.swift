import AppKit
import SwiftUI

struct OnboardingView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Accessibility Required")
                .font(.title2)
                .fontWeight(.semibold)
            Text("edith reads your selection and replaces it with a transformed version. Grant Accessibility access in System Settings, then relaunch edith.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            Button("Open System Settings") {
                openAccessibilityPane()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(32)
        .frame(minWidth: 460, minHeight: 280)
    }

    private func openAccessibilityPane() {
        guard let url = AccessibilityDeepLink.url else { return }
        NSWorkspace.shared.open(url)
    }
}
