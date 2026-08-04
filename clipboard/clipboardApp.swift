import SwiftUI

@main
struct ClipboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        MenuBarExtra("clipboard", systemImage: "doc.on.clipboard") {
            SettingsLink {
                Label("Definições…", systemImage: "gearshape")
            }

            Divider()

            Button("Sair") {
                NSApp.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)

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
        NSApp.setActivationPolicy(.accessory)
        AppState.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.stop()
    }
}
