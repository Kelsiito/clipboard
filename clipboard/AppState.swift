import ApplicationServices
import AppKit
import Carbon.HIToolbox
import Foundation
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

enum HotKeyTarget: String, Equatable {
    case history
    case gif
}

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
            guard hotKey != gifHotKey else {
                statusMessage = "History and GIF hotkeys must be different."
                hotKey = oldHotKey
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

    @Published var gifHotKey: HotKeyConfiguration {
        didSet {
            UserDefaults.standard.set(try? JSONEncoder().encode(gifHotKey), forKey: Keys.gifHotKey)
            guard hasStarted else {
                oldGIFHotKey = gifHotKey
                return
            }
            guard gifHotKey != hotKey else {
                statusMessage = "History and GIF hotkeys must be different."
                gifHotKey = oldGIFHotKey
                return
            }
            if !gifHotKeyManager.register(gifHotKey) {
                statusMessage = "GIF hotkey unavailable; previous configuration kept."
                gifHotKey = oldGIFHotKey
            } else {
                oldGIFHotKey = gifHotKey
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

    @Published var launchAtLogin: Bool {
        didSet {
            guard !isUpdatingLaunchAtLogin else { return }
            let requestedValue = launchAtLogin
            do {
                if requestedValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                UserDefaults.standard.set(requestedValue, forKey: Keys.launchAtLogin)
            } catch {
                isUpdatingLaunchAtLogin = true
                launchAtLogin = !requestedValue
                isUpdatingLaunchAtLogin = false
                statusMessage = "Launch at login could not be changed."
            }
        }
    }

    @Published private(set) var isAccessibilityTrusted = AXIsProcessTrusted()
    @Published private(set) var isRecordingHotKey = false
    @Published private(set) var isCapturingScreenshot = false
    @Published private(set) var isRecordingGIF = false
    @Published var statusMessage: String?

    let store: ClipboardStore

    private let monitor = PasteboardMonitor()
    private let hotKeyManager = GlobalHotKeyManager(identifier: 1)
    private let gifHotKeyManager = GlobalHotKeyManager(identifier: 2)
    private let panelController = ClipboardPanelController()
    private let screenshotCaptureService = ScreenshotCaptureService()
    private let screenGIFRecorder = ScreenGIFRecorder()
    private let annotationEditorController = AnnotationEditorController()
    private var settingsWindow: NSWindow?
    private var targetApplication: NSRunningApplication?
    private var recordingMonitor: Any?
    private var accessibilityTimer: Timer?
    private var hasStarted = false
    private var isUpdatingLaunchAtLogin = false
    private var oldHotKey: HotKeyConfiguration
    private var oldGIFHotKey: HotKeyConfiguration
    private var recordingHotKeyTarget: HotKeyTarget?
    private enum Keys {
        static let hotKey = "clipboard.hotKey"
        static let gifHotKey = "clipboard.gifHotKey"
        static let historyLimit = "clipboard.historyLimit"
        static let appearance = "clipboard.appearance"
        static let material = "clipboard.material"
        static let launchAtLogin = "clipboard.launchAtLogin"
    }

    private init() {
        store = ClipboardStore(limit: UserDefaults.standard.integer(forKey: Keys.historyLimit) == 0 ? 50 : UserDefaults.standard.integer(forKey: Keys.historyLimit))
        let savedHotKey = (UserDefaults.standard.data(forKey: Keys.hotKey).flatMap { try? JSONDecoder().decode(HotKeyConfiguration.self, from: $0) }) ?? .default
        let savedGIFHotKey = (UserDefaults.standard.data(forKey: Keys.gifHotKey).flatMap { try? JSONDecoder().decode(HotKeyConfiguration.self, from: $0) }) ?? .gifDefault
        let savedAppearance = UserDefaults.standard.string(forKey: Keys.appearance)
            .flatMap(ClipboardAppearance.init(rawValue:)) ?? .system
        let savedMaterial = UserDefaults.standard.string(forKey: Keys.material)
            .flatMap(ClipboardMaterial.init(rawValue:)) ?? .liquidGlass
        hotKey = savedHotKey
        oldHotKey = savedHotKey
        gifHotKey = savedGIFHotKey
        oldGIFHotKey = savedGIFHotKey
        historyLimit = store.limit
        appearance = savedAppearance
        material = savedMaterial
        launchAtLogin = SMAppService.mainApp.status == .enabled

        hotKeyManager.onHotKey = { [weak self] in
            self?.showPanel()
        }
        gifHotKeyManager.onHotKey = { [weak self] in
            self?.toggleGIFRecording()
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
        oldGIFHotKey = gifHotKey
        if !hotKeyManager.register(hotKey) {
            statusMessage = "Could not register \(hotKey.displayString)."
        }
        if !gifHotKeyManager.register(gifHotKey) {
            statusMessage = "Could not register \(gifHotKey.displayString) for GIF recording."
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
        gifHotKeyManager.stop()
        screenGIFRecorder.cancel()
        annotationEditorController.close()
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
            onTogglePin: { [weak self] item in self?.togglePin(item) },
            onEdit: { [weak self] item in self?.editImage(item) },
            onDelete: { [weak self] item in self?.deleteItem(item) }
        )
    }

    func editImage(_ item: ClipboardItem) {
        guard item.hasImage, !item.isGIF, let imageData = item.imageData,
              let image = NSImage(data: imageData) else {
            statusMessage = "This item cannot be edited."
            return
        }

        panelController.close()
        annotationEditorController.show(
            image: image,
            appearance: appearance,
            material: material,
            onCopy: { [weak self] data in self?.copyAnnotatedScreenshot(data) }
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

    func deleteItem(_ item: ClipboardItem) {
        guard store.remove(item.id) else { return }
        statusMessage = "Item deleted."
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

    func clearUnpinnedHistory() {
        let removedCount = store.clearUnpinned()
        statusMessage = removedCount == 0
            ? "No unpinned items to clear."
            : "Cleared \(removedCount) unpinned item\(removedCount == 1 ? "" : "s")."
    }

    func ignoreNextCopy() {
        monitor.ignoreNextCopy()
        statusMessage = "Next clipboard copy will be ignored."
    }

    func beginRecordingHotKey() {
        beginRecordingHotKey(for: .history)
    }

    func beginRecordingHotKey(for target: HotKeyTarget) {
        stopRecordingHotKey()
        recordingHotKeyTarget = target
        isRecordingHotKey = true
        let prompt = target == .gif ? "Press a new GIF combination…" : "Press a new history combination…"
        statusMessage = prompt
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 {
                self.stopRecordingHotKey()
                return nil
            }
            let modifiers = HotKeyConfiguration.modifiers(from: event.modifierFlags)
            guard modifiers != 0 else { return event }
            let candidate = HotKeyConfiguration(keyCode: UInt32(event.keyCode), modifiers: modifiers)
            let registered: Bool
            switch target {
            case .history:
                registered = self.hotKeyManager.register(candidate)
                if registered {
                    self.oldHotKey = self.hotKey
                    self.hotKey = candidate
                }
            case .gif:
                registered = self.gifHotKeyManager.register(candidate)
                if registered {
                    self.oldGIFHotKey = self.gifHotKey
                    self.gifHotKey = candidate
                }
            }
            if registered {
                self.statusMessage = "Hotkey set: \(candidate.displayString)"
            } else {
                self.statusMessage = "Combination unavailable."
            }
            self.stopRecordingHotKey()
            return nil
        }
    }

    func stopRecordingHotKey() {
        if let recordingMonitor { NSEvent.removeMonitor(recordingMonitor) }
        recordingMonitor = nil
        let shouldClearPrompt = statusMessage?.hasPrefix("Press a new") == true
        recordingHotKeyTarget = nil
        isRecordingHotKey = false
        if shouldClearPrompt {
            statusMessage = nil
        }
    }

    func isRecordingHotKey(for target: HotKeyTarget) -> Bool {
        isRecordingHotKey && recordingHotKeyTarget == target
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    func captureAndAnnotate() {
        guard !isCapturingScreenshot else {
            statusMessage = "A screen capture is already in progress."
            return
        }

        panelController.close()
        annotationEditorController.close()
        settingsWindow?.orderOut(nil)
        isCapturingScreenshot = true
        statusMessage = "Select an area to capture…"

        screenshotCaptureService.captureSelection { [weak self] result in
            guard let self else { return }
            self.isCapturingScreenshot = false
            switch result {
            case .success(let image):
                self.statusMessage = nil
                self.annotationEditorController.show(
                    image: image,
                    appearance: self.appearance,
                    material: self.material,
                    onCopy: { [weak self] data in self?.copyAnnotatedScreenshot(data) }
                )
            case .failure(.cancelled):
                self.statusMessage = nil
            case .failure(let error):
                self.statusMessage = error.localizedDescription
            }
        }
    }

    private func copyAnnotatedScreenshot(_ data: Data) {
        let pasteboard = NSPasteboard.general
        monitor.suppressCapture()
        pasteboard.clearContents()
        guard pasteboard.setData(data, forType: .png) else {
            statusMessage = "The annotated screenshot could not be copied."
            return
        }
        store.ingest(ClipboardSnapshot(
            text: nil,
            richTextData: nil,
            imageData: data,
            imageType: NSPasteboard.PasteboardType.png.rawValue,
            fileURLs: []
        ))
        statusMessage = "Annotated screenshot copied to the clipboard."
    }

    func recordGIF() {
        guard !isRecordingGIF else {
            statusMessage = "A GIF recording is already in progress."
            return
        }

        panelController.close()
        annotationEditorController.close()
        settingsWindow?.orderOut(nil)
        isRecordingGIF = true
        statusMessage = "Drag to select an area. Release to start recording."

        screenGIFRecorder.start { [weak self] result in
            guard let self else { return }
            self.isRecordingGIF = false
            switch result {
            case .success(let data):
                self.copyGIFToClipboard(data)
            case .failure(.cancelled):
                self.statusMessage = nil
            case .failure(let error):
                self.statusMessage = error.localizedDescription
            }
        }
    }

    func toggleGIFRecording() {
        if isRecordingGIF {
            finishGIFRecording()
        } else {
            recordGIF()
        }
    }

    func cancelGIFRecording() {
        guard isRecordingGIF else { return }
        statusMessage = "Cancelling GIF recording…"
        screenGIFRecorder.cancel()
    }

    func finishGIFRecording() {
        guard isRecordingGIF else { return }
        statusMessage = "Finishing GIF recording…"
        screenGIFRecorder.finish()
    }

    private func copyGIFToClipboard(_ data: Data) {
        let pasteboard = NSPasteboard.general
        let gifType = NSPasteboard.PasteboardType(UTType.gif.identifier)
        monitor.suppressCapture()
        pasteboard.clearContents()
        guard pasteboard.setData(data, forType: gifType) else {
            statusMessage = "The GIF could not be copied to the clipboard."
            return
        }

        store.ingest(ClipboardSnapshot(
            text: nil,
            richTextData: nil,
            imageData: data,
            imageType: gifType.rawValue,
            fileURLs: []
        ))
        statusMessage = "GIF copied to the clipboard. Press ⌘V to paste."
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
