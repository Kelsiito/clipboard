import ApplicationServices
import SwiftUI

extension View {
    @ViewBuilder
    func clipboardGlassSurface<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }

    @ViewBuilder
    func clipboardGlassButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    func clipboardGlassEntranceTransition() -> some View {
        if #available(macOS 26.0, *) {
            glassEffectTransition(.materialize)
        } else {
            self
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showingClearConfirmation = false

    var body: some View {
        Form {
            Section("Hotkey") {
                HStack {
                    Text("Open history")
                    Spacer()
                    Text(appState.isRecordingHotKey ? "Press a new combination…" : appState.hotKey.displayString)
                        .monospaced()
                        .foregroundStyle(.secondary)
                    Button(appState.isRecordingHotKey ? "Cancel" : "Change") {
                        if appState.isRecordingHotKey { appState.stopRecordingHotKey() } else { appState.beginRecordingHotKey() }
                    }
                }
            }

            Section("History") {
                Stepper(value: $appState.historyLimit, in: 10...200, step: 10) {
                    HStack {
                        Text("Stored items")
                        Spacer()
                        Text("\(appState.historyLimit)")
                            .foregroundStyle(.secondary)
                    }
                }

                Button("Clear history", role: .destructive) {
                    showingClearConfirmation = true
                }
            }

            Section("Automatic paste") {
                HStack {
                    Label("Accessibility", systemImage: appState.isAccessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    Spacer()
                    Text(appState.isAccessibilityTrusted ? "Active" : "Required")
                        .foregroundStyle(appState.isAccessibilityTrusted ? .green : .orange)
                }
                if !appState.isAccessibilityTrusted {
                    Button("Open System Settings") {
                        appState.openAccessibilitySettings()
                    }
                }
            }

            if let statusMessage = appState.statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(.clear)
        .frame(width: 460, height: 468)
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .clipboardGlassSurface(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 0.5)
        }
        .padding(16)
        .confirmationDialog("Clear history?", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { appState.clearHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes text, images, and references stored by the app.")
        }
    }
}
