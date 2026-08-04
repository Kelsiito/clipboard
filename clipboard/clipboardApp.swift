import SwiftUI

@main
struct ClipboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        MenuBarExtra("clipboard", systemImage: "doc.on.clipboard") {
            Button {
                appState.showSettings()
            } label: {
                Label("Settings…", systemImage: "gearshape")
            }

            Divider()

            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppState.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.stop()
    }
}
