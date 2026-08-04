import ApplicationServices
import AppKit
import Carbon.HIToolbox
import Foundation
import SwiftUI

enum ClipboardAppearance: String, CaseIterable, Hashable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

enum ClipboardMaterial: String, CaseIterable, Hashable, Identifiable {
    case liquidGlass
    case standard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .liquidGlass: return "Liquid Glass"
        case .standard: return "Standard"
        }
    }
}

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
                statusMessage = "Hotkey unavailable; previous configuration kept."
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

    @Published var appearance: ClipboardAppearance {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: Keys.appearance)
            applyAppearance(appearance, to: settingsWindow)
            panelController.setAppearance(appearance)
        }
    }

    @Published var material: ClipboardMaterial {
        didSet {
            UserDefaults.standard.set(material.rawValue, forKey: Keys.material)
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
        static let appearance = "clipboard.appearance"
        static let material = "clipboard.material"
    }

    private init() {
        store = ClipboardStore(limit: UserDefaults.standard.integer(forKey: Keys.historyLimit) == 0 ? 50 : UserDefaults.standard.integer(forKey: Keys.historyLimit))
        let savedHotKey = (UserDefaults.standard.data(forKey: Keys.hotKey).flatMap { try? JSONDecoder().decode(HotKeyConfiguration.self, from: $0) }) ?? .default
        let savedAppearance = UserDefaults.standard.string(forKey: Keys.appearance)
            .flatMap(ClipboardAppearance.init(rawValue:)) ?? .system
        let savedMaterial = UserDefaults.standard.string(forKey: Keys.material)
            .flatMap(ClipboardMaterial.init(rawValue:)) ?? .liquidGlass
        hotKey = savedHotKey
        oldHotKey = savedHotKey
        historyLimit = store.limit
        appearance = savedAppearance
        material = savedMaterial

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
            statusMessage = "Could not register \(hotKey.displayString)."
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
            statusMessage = "Enable Accessibility to position the picker near the field and paste automatically."
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }

        panelController.show(
            store: store,
            targetApplication: targetApplication,
            appearance: appearance,
            material: material,
            onPaste: { [weak self] item, format in self?.paste(item, format: format) },
            onTogglePin: { [weak self] item in self?.togglePin(item) }
        )
    }

    func togglePin(_ item: ClipboardItem) {
        let shouldPin = !item.isPinned
        guard store.setPinned(item.id, pinned: shouldPin) else {
            if shouldPin {
                statusMessage = "Maximum of 3 pinned items."
            }
            return
        }
    }

    func showSettings() {
        panelController.close()

        if settingsWindow == nil {
            let settingsSize = NSSize(width: 520, height: 500)
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: settingsSize),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.appearance = appearance.nsAppearance
            window.setContentSize(settingsSize)
            window.minSize = settingsSize
            window.title = "Settings — clipboard"
            window.titlebarAppearsTransparent = false
            window.titleVisibility = .visible
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.hidesOnDeactivate = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.standardWindowButton(.closeButton)?.isEnabled = true
            window.standardWindowButton(.miniaturizeButton)?.isEnabled = true

            let rootView = SettingsView()
                .environmentObject(self)
                .frame(width: settingsSize.width, height: settingsSize.height, alignment: .top)
            let hostingController = NSHostingController(rootView: rootView)
            hostingController.view.frame = NSRect(origin: .zero, size: settingsSize)
            hostingController.view.autoresizingMask = [.width, .height]
            window.contentViewController = hostingController

            window.center()
            settingsWindow = window
        }

        applyAppearance(appearance, to: settingsWindow)
        settingsWindow?.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.orderFrontRegardless()
        settingsWindow?.makeKey()
    }

    private func applyAppearance(_ appearance: ClipboardAppearance, to window: NSWindow?) {
        window?.appearance = appearance.nsAppearance
        window?.contentView?.appearance = appearance.nsAppearance
        window?.backgroundColor = .windowBackgroundColor
        window?.contentView?.needsDisplay = true
    }

    func clearHistory() {
        store.clear()
        statusMessage = "History cleared."
    }

    func beginRecordingHotKey() {
        stopRecordingHotKey()
        isRecordingHotKey = true
        statusMessage = "Press a new combination…"
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
                self.statusMessage = "Hotkey set: \(candidate.displayString)"
                self.stopRecordingHotKey()
            } else {
                self.statusMessage = "Combination unavailable."
                self.stopRecordingHotKey()
            }
            return nil
        }
    }

    func stopRecordingHotKey() {
        if let recordingMonitor { NSEvent.removeMonitor(recordingMonitor) }
        recordingMonitor = nil
        isRecordingHotKey = false
        if statusMessage == "Press a new combination…" {
            statusMessage = nil
        }
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    private func paste(_ item: ClipboardItem, format: ClipboardPasteFormat = .original) {
        guard let payload = ClipboardPasteFormatter.payload(for: item, format: format) else {
            statusMessage = "\(format.title) is unavailable for this item."
            return
        }

        panelController.close()
        let pasteboard = NSPasteboard.general
        monitor.suppressCapture()
        pasteboard.clearContents()

        if let text = payload.text { pasteboard.setString(text, forType: .string) }
        if let richTextData = payload.richTextData { pasteboard.setData(richTextData, forType: .rtf) }
        if let imageData = payload.imageData, let imageType = payload.imageType {
            pasteboard.setData(imageData, forType: NSPasteboard.PasteboardType(imageType))
        }
        let urls = payload.fileURLs
        if !urls.isEmpty { pasteboard.writeObjects(urls as [NSURL]) }

        guard let targetApplication else { return }
        guard AXIsProcessTrusted() else {
            statusMessage = "Enable Accessibility for automatic paste."
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
