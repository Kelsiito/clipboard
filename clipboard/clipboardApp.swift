import SwiftUI

@main
struct ClipboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {}
            CommandGroup(replacing: .appSettings) {
                SettingsLink {
                    Text("Definições…")
                }
            }
            CommandGroup(replacing: .appTermination) {
                Button("Sair") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        AppState.shared.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppState.shared.showPanel()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.stop()
    }
}
