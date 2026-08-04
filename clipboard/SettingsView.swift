import ApplicationServices
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showingClearConfirmation = false

    var body: some View {
        Form {
            Section("Hotkey") {
                HStack {
                    Text("Abrir histórico")
                    Spacer()
                    Text(appState.isRecordingHotKey ? "Prima combinação…" : appState.hotKey.displayString)
                        .monospaced()
                        .foregroundStyle(.secondary)
                    Button(appState.isRecordingHotKey ? "Cancelar" : "Alterar") {
                        if appState.isRecordingHotKey { appState.stopRecordingHotKey() } else { appState.beginRecordingHotKey() }
                    }
                }
            }

            Section("Histórico") {
                Stepper(value: $appState.historyLimit, in: 10...200, step: 10) {
                    HStack {
                        Text("Itens guardados")
                        Spacer()
                        Text("\(appState.historyLimit)")
                            .foregroundStyle(.secondary)
                    }
                }

                Button("Limpar histórico", role: .destructive) {
                    showingClearConfirmation = true
                }
            }

            Section("Colagem automática") {
                HStack {
                    Label("Accessibility", systemImage: appState.isAccessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    Spacer()
                    Text(appState.isAccessibilityTrusted ? "Ativo" : "Necessário")
                        .foregroundStyle(appState.isAccessibilityTrusted ? .green : .orange)
                }
                if !appState.isAccessibilityTrusted {
                    Button("Abrir Definições do Sistema") {
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
        .frame(width: 460)
        .padding(.vertical, 12)
        .confirmationDialog("Limpar histórico?", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
            Button("Limpar", role: .destructive) { appState.clearHistory() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Remove texto, imagens e referências guardadas pela app.")
        }
    }
}
