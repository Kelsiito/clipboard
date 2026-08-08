import ApplicationServices
import SwiftUI

extension View {
    @ViewBuilder
    func clipboardGlassSurface<S: Shape>(in shape: S, material: ClipboardMaterial = .liquidGlass) -> some View {
        if material == .liquidGlass, #available(macOS 26.0, *) {
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
    func clipboardGlassEntranceTransition(material: ClipboardMaterial = .liquidGlass) -> some View {
        if material == .liquidGlass, #available(macOS 26.0, *) {
            glassEffectTransition(.materialize)
        } else {
            self
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showingClearConfirmation = false
    @State private var showingClearUnpinnedConfirmation = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                settingsSection("Hotkeys") {
                    settingsCard {
                        VStack(spacing: 0) {
                            hotKeyRow(
                                title: "Open history",
                                configuration: appState.hotKey,
                                target: .history
                            )

                            Divider()
                                .padding(.vertical, 12)

                            hotKeyRow(
                                title: "Record GIF",
                                configuration: appState.gifHotKey,
                                target: .gif
                            )
                        }
                    }
                }

                settingsSection("History") {
                    settingsCard {
                        VStack(spacing: 0) {
                            HStack {
                                Text("Stored items")
                                Spacer()
                                Stepper(value: $appState.historyLimit, in: 10...200, step: 10) {
                                    Text("\(appState.historyLimit)")
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                                .controlSize(.small)
                            }

                            Divider()
                                .padding(.vertical, 12)

                            HStack {
                                Button("Clear history", role: .destructive) {
                                    showingClearConfirmation = true
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                Spacer()
                            }

                            Divider()
                                .padding(.vertical, 12)

                            HStack {
                                Button("Clear unpinned", role: .destructive) {
                                    showingClearUnpinnedConfirmation = true
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                Spacer()
                            }

                            Divider()
                                .padding(.vertical, 12)

                            HStack {
                                Text("Retention")
                                Spacer()
                                Picker("Retention", selection: $appState.retention) {
                                    ForEach(ClipboardRetention.allCases) { option in
                                        Text(option.title).tag(option)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .controlSize(.small)
                            }

                            Text("Unpinned items older than this are removed automatically. Pinned items are kept.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 8)
                        }
                    }
                }

                settingsSection("Privacy") {
                    settingsCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label(
                                    appState.isHistoryPaused ? "History paused" : "History capture",
                                    systemImage: appState.isHistoryPaused ? "pause.circle.fill" : "record.circle"
                                )
                                Spacer()
                                if appState.isHistoryPaused {
                                    Button("Resume") { appState.resumeHistory() }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                } else {
                                    Menu("Pause") {
                                        ForEach(ClipboardPauseDuration.allCases) { duration in
                                            Button(duration.title) {
                                                appState.pauseHistory(for: duration)
                                            }
                                        }
                                    }
                                    .controlSize(.small)
                                }
                            }

                            Divider()

                            Text("Ignore applications")
                                .font(.subheadline.weight(.semibold))

                            if appState.availableApplications.isEmpty {
                                Text("No other running applications found.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(appState.availableApplications) { application in
                                    Toggle(isOn: Binding(
                                        get: { appState.isApplicationIgnored(application.bundleIdentifier) },
                                        set: { appState.setApplicationIgnored(application.bundleIdentifier, ignored: $0) }
                                    )) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(application.displayName)
                                            Text(application.bundleIdentifier)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .toggleStyle(.checkbox)
                                }
                            }

                            Text("Copies made while an ignored application is active are not stored.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                settingsSection("Startup") {
                    settingsCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Launch at login", isOn: $appState.launchAtLogin)
                            Text("Start clipboard automatically after you sign in.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                settingsSection("Appearance") {
                    settingsCard {
                        VStack(alignment: .leading, spacing: 0) {
                            appearancePicker(
                                title: "Color scheme",
                                selection: $appState.appearance,
                                options: ClipboardAppearance.allCases
                            )

                            Divider()
                                .padding(.vertical, 10)

                            appearancePicker(
                                title: "Material",
                                selection: $appState.material,
                                options: ClipboardMaterial.allCases
                            )

                            Text("Liquid Glass uses the native glass surface on macOS 26 or later and a material fallback on earlier versions.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 12)
                        }
                    }
                }

                settingsSection("Automatic paste") {
                    settingsCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label(
                                    "Accessibility",
                                    systemImage: appState.isAccessibilityTrusted
                                        ? "checkmark.circle.fill"
                                        : "exclamationmark.triangle.fill"
                                )
                                Spacer()
                                Text(appState.isAccessibilityTrusted ? "Active" : "Required")
                                    .foregroundStyle(appState.isAccessibilityTrusted ? .green : .orange)
                            }

                            if !appState.isAccessibilityTrusted {
                                Button("Open System Settings") {
                                    appState.openAccessibilitySettings()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }

                if let statusMessage = appState.statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(22)
        }
        .frame(width: 520, height: 500)
        .confirmationDialog("Clear history?", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { appState.clearHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes text, images, and references stored by the app.")
        }
        .confirmationDialog("Clear unpinned history?", isPresented: $showingClearUnpinnedConfirmation, titleVisibility: .visible) {
            Button("Clear unpinned", role: .destructive) { appState.clearUnpinnedHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pinned items and original files remain untouched.")
        }
        .task {
            appState.refreshAvailableApplications()
        }
    }

    @ViewBuilder
    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    private func settingsCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(14)
            .background(
                Color.primary.opacity(0.065),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
    }

    private func hotKeyRow(
        title: String,
        configuration: HotKeyConfiguration,
        target: HotKeyTarget
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 12)
            Text(appState.isRecordingHotKey(for: target) ? "Press a new combination…" : configuration.displayString)
                .monospaced()
                .foregroundStyle(.secondary)
            Button(appState.isRecordingHotKey(for: target) ? "Cancel" : "Change") {
                if appState.isRecordingHotKey(for: target) {
                    appState.stopRecordingHotKey()
                } else {
                    appState.beginRecordingHotKey(for: target)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func appearancePicker<Option: Hashable & Identifiable>(
        title: String,
        selection: Binding<Option>,
        options: [Option]
    ) -> some View where Option.ID == String {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            Picker(title, selection: selection) {
                ForEach(options) { option in
                    Text(optionTitle(option)).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
        }
    }

    private func optionTitle<Option>(_ option: Option) -> String {
        if let appearance = option as? ClipboardAppearance { return appearance.title }
        if let material = option as? ClipboardMaterial { return material.title }
        return String(describing: option)
    }
}
