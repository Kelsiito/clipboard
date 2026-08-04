import ApplicationServices
import AppKit
import Carbon.HIToolbox
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var hotKey: HotKeyConfiguration {
        didSet {
            UserDefaults.standard.set(try? JSONEncoder().encode(hotKey), forKey: Keys.hotKey)
            guard hasStarted else {
                oldHotKey = hotKey
                return
            }
            if !hotKeyManager.register(hotKey) {
                statusMessage = "Hotkey indisponível; mantida configuração anterior."
                hotKey = oldHotKey
            } else {
                oldHotKey = hotKey
            }
        }
    }

    @Published var historyLimit: Int {
        didSet {
            historyLimit = min(max(historyLimit, 10), 200)
            UserDefaults.standard.set(historyLimit, forKey: Keys.historyLimit)
            store.setLimit(historyLimit)
        }
    }

    @Published private(set) var isAccessibilityTrusted = AXIsProcessTrusted()
    @Published private(set) var isRecordingHotKey = false
    @Published var statusMessage: String?

    let store: ClipboardStore

    private let monitor = PasteboardMonitor()
    private let hotKeyManager = GlobalHotKeyManager()
    private let panelController = ClipboardPanelController()
    private var settingsWindow: NSWindow?
    private var targetApplication: NSRunningApplication?
    private var recordingMonitor: Any?
    private var accessibilityTimer: Timer?
    private var hasStarted = false
    private var oldHotKey: HotKeyConfiguration

    private enum Keys {
        static let hotKey = "clipboard.hotKey"
        static let historyLimit = "clipboard.historyLimit"
    }

    private init() {
        store = ClipboardStore(limit: UserDefaults.standard.integer(forKey: Keys.historyLimit) == 0 ? 50 : UserDefaults.standard.integer(forKey: Keys.historyLimit))
        let savedHotKey = (UserDefaults.standard.data(forKey: Keys.hotKey).flatMap { try? JSONDecoder().decode(HotKeyConfiguration.self, from: $0) }) ?? .default
        hotKey = savedHotKey
        oldHotKey = savedHotKey
        historyLimit = store.limit

        hotKeyManager.onHotKey = { [weak self] in
            self?.showPanel()
        }
        monitor.onSnapshot = { [weak self] snapshot in
            self?.store.ingest(snapshot)
        }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        monitor.start()
        oldHotKey = hotKey
        if !hotKeyManager.register(hotKey) {
            statusMessage = "Não foi possível registar \(hotKey.displayString)."
        }
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isAccessibilityTrusted = AXIsProcessTrusted()
            }
        }
    }

    func stop() {
        monitor.stop()
        hotKeyManager.stop()
        accessibilityTimer?.invalidate()
        accessibilityTimer = nil
        stopRecordingHotKey()
    }

    func showPanel() {
        let currentProcessIdentifier = NSRunningApplication.current.processIdentifier
        targetApplication = panelController.targetApplication(
            excluding: currentProcessIdentifier
        )

        if !AXIsProcessTrusted() {
            statusMessage = "Ative Accessibility para posicionar junto ao campo e colar automaticamente."
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }

        panelController.show(
            store: store,
            targetApplication: targetApplication,
            onSelect: { [weak self] item in self?.paste(item) },
            onTogglePin: { [weak self] item in self?.togglePin(item) }
        )
    }

    func togglePin(_ item: ClipboardItem) {
        let shouldPin = !item.isPinned
        guard store.setPinned(item.id, pinned: shouldPin) else {
            if shouldPin {
                statusMessage = "Máximo de 3 itens afixados."
            }
            return
        }
    }

    func showSettings() {
        panelController.close()

        if settingsWindow == nil {
            let settingsSize = NSSize(width: 520, height: 500)
            let rootView = SettingsView()
                .environmentObject(self)
                .frame(width: settingsSize.width, height: settingsSize.height, alignment: .top)
            let hostingController = NSHostingController(rootView: rootView)
            hostingController.view.frame = NSRect(origin: .zero, size: settingsSize)
            hostingController.view.autoresizingMask = [.width, .height]

            let window = NSWindow(contentViewController: hostingController)
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(settingsSize)
            window.minSize = settingsSize
            window.title = "Definições — clipboard"
            window.titlebarAppearsTransparent = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.hidesOnDeactivate = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.center()
            settingsWindow = window
        }

        settingsWindow?.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.orderFrontRegardless()
        settingsWindow?.makeKey()
    }

    func clearHistory() {
        store.clear()
        statusMessage = "Histórico limpo."
    }

    func beginRecordingHotKey() {
        stopRecordingHotKey()
        isRecordingHotKey = true
        statusMessage = "Prima nova combinação…"
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 {
                self.stopRecordingHotKey()
                return nil
            }
            let modifiers = HotKeyConfiguration.modifiers(from: event.modifierFlags)
            guard modifiers != 0 else { return event }
            let candidate = HotKeyConfiguration(keyCode: UInt32(event.keyCode), modifiers: modifiers)
            if self.hotKeyManager.register(candidate) {
                self.oldHotKey = self.hotKey
                self.hotKey = candidate
                self.statusMessage = "Hotkey definida: \(candidate.displayString)"
                self.stopRecordingHotKey()
            } else {
                self.statusMessage = "Combinação indisponível."
                self.stopRecordingHotKey()
            }
            return nil
        }
    }

    func stopRecordingHotKey() {
        if let recordingMonitor { NSEvent.removeMonitor(recordingMonitor) }
        recordingMonitor = nil
        isRecordingHotKey = false
        if statusMessage == "Prima nova combinação…" {
            statusMessage = nil
        }
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    private func paste(_ item: ClipboardItem) {
        panelController.close()
        let pasteboard = NSPasteboard.general
        monitor.suppressCapture()
        pasteboard.clearContents()

        if let text = item.text { pasteboard.setString(text, forType: .string) }
        if let richTextData = item.richTextData { pasteboard.setData(richTextData, forType: .rtf) }
        if let imageData = item.imageData, let imageType = item.imageType {
            pasteboard.setData(imageData, forType: NSPasteboard.PasteboardType(imageType))
        }
        let urls = item.files.compactMap(\.resolvedURL)
        if !urls.isEmpty { pasteboard.writeObjects(urls as [NSURL]) }

        guard let targetApplication else { return }
        guard AXIsProcessTrusted() else {
            statusMessage = "Ative Accessibility para colagem automática."
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            return
        }

        targetApplication.activate(options: [])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            let source = CGEventSource(stateID: .hidSystemState)
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
            keyDown?.flags = .maskCommand
            keyUp?.flags = .maskCommand
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        }
    }
}
