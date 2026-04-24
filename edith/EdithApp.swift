import SwiftUI

@main
struct EdithApp: App {
    var body: some Scene {
        MenuBarExtra("edith", systemImage: "sparkles") {
            Text("edith — walking skeleton")
                .padding(8)
        }
        .menuBarExtraStyle(.menu)
    }
}
