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
    case stackStart
    case stackNext
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

struct ClipboardApplication: Identifiable, Hashable {
    let bundleIdentifier: String
    let displayName: String

    var id: String { bundleIdentifier }
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
            guard !isHotKeyInUse(hotKey, excluding: .history) else {
                statusMessage = "Hotkeys must be different."
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
            guard !isHotKeyInUse(gifHotKey, excluding: .gif) else {
                statusMessage = "Hotkeys must be different."
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

    @Published var stackStartHotKey: HotKeyConfiguration? {
        didSet {
            persistOptionalHotKey(stackStartHotKey, key: Keys.stackStartHotKey)
            guard hasStarted else {
                oldStackStartHotKey = stackStartHotKey
                return
            }
            guard !isHotKeyInUse(stackStartHotKey, excluding: .stackStart) else {
                statusMessage = "That hotkey is already in use."
                stackStartHotKey = oldStackStartHotKey
                return
            }
            if !stackStartHotKeyManager.register(stackStartHotKey) {
                statusMessage = "Hotkey unavailable; previous configuration kept."
                stackStartHotKey = oldStackStartHotKey
            } else {
                oldStackStartHotKey = stackStartHotKey
            }
        }
    }

    @Published var stackNextHotKey: HotKeyConfiguration? {
        didSet {
            persistOptionalHotKey(stackNextHotKey, key: Keys.stackNextHotKey)
            guard hasStarted else {
                oldStackNextHotKey = stackNextHotKey
                return
            }
            guard !isHotKeyInUse(stackNextHotKey, excluding: .stackNext) else {
                statusMessage = "That hotkey is already in use."
                stackNextHotKey = oldStackNextHotKey
                return
            }
            if !stackNextHotKeyManager.register(stackNextHotKey) {
                statusMessage = "Hotkey unavailable; previous configuration kept."
                stackNextHotKey = oldStackNextHotKey
            } else {
                oldStackNextHotKey = stackNextHotKey
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

    @Published var retention: ClipboardRetention {
        didSet {
            UserDefaults.standard.set(retention.rawValue, forKey: Keys.retention)
            store.setRetention(retention)
        }
    }

    @Published var ignoredBundleIdentifiers: Set<String> = [] {
        didSet {
            UserDefaults.standard.set(Array(ignoredBundleIdentifiers).sorted(), forKey: Keys.ignoredBundleIdentifiers)
            monitor.ignoredBundleIdentifiers = ignoredBundleIdentifiers
            refreshAvailableApplications()
        }
    }

    @Published private(set) var availableApplications: [ClipboardApplication] = []
    @Published private(set) var isHistoryPaused = false
    @Published private(set) var isCapturingStack = false
    @Published private(set) var clipboardStack = ClipboardStack()

    @Published var appearance: ClipboardAppearance {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: Keys.appearance)
            applyAppearance(appearance, to: settingsWindow)
            applyAppearance(appearance, to: favoritesWindow)
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
    let snippetStore: SnippetStore

    private let monitor = PasteboardMonitor()
    private let hotKeyManager = GlobalHotKeyManager(identifier: 1)
    private let gifHotKeyManager = GlobalHotKeyManager(identifier: 2)
    private let stackStartHotKeyManager = GlobalHotKeyManager(identifier: 3)
    private let stackNextHotKeyManager = GlobalHotKeyManager(identifier: 4)
    private let panelController = ClipboardPanelController()
    private let screenshotCaptureService = ScreenshotCaptureService()
    private let screenGIFRecorder = ScreenGIFRecorder()
    private let quickLookPreview = ClipboardQuickLookPreview()
    private let annotationEditorController = AnnotationEditorController()
    private var settingsWindow: NSWindow?
    private var favoritesWindow: NSWindow?
    private var targetApplication: NSRunningApplication?
    private var recordingMonitor: Any?
    private var accessibilityTimer: Timer?
    private var hasStarted = false
    private var isUpdatingLaunchAtLogin = false
    private var oldHotKey: HotKeyConfiguration
    private var oldGIFHotKey: HotKeyConfiguration
    private var oldStackStartHotKey: HotKeyConfiguration?
    private var oldStackNextHotKey: HotKeyConfiguration?
    private var recordingHotKeyTarget: HotKeyTarget?
    private enum Keys {
        static let hotKey = "clipboard.hotKey"
        static let gifHotKey = "clipboard.gifHotKey"
        static let stackStartHotKey = "clipboard.stackStartHotKey"
        static let stackNextHotKey = "clipboard.stackNextHotKey"
        static let historyLimit = "clipboard.historyLimit"
        static let retention = "clipboard.retention"
        static let ignoredBundleIdentifiers = "clipboard.ignoredBundleIdentifiers"
        static let appearance = "clipboard.appearance"
        static let material = "clipboard.material"
        static let launchAtLogin = "clipboard.launchAtLogin"
    }

    private init() {
        let savedHistoryLimit = UserDefaults.standard.integer(forKey: Keys.historyLimit)
        let savedRetention = UserDefaults.standard.string(forKey: Keys.retention)
            .flatMap(ClipboardRetention.init(rawValue:)) ?? .never
        store = ClipboardStore(
            limit: savedHistoryLimit == 0 ? 50 : savedHistoryLimit,
            retention: savedRetention
        )
        snippetStore = SnippetStore()
        let savedHotKey = (UserDefaults.standard.data(forKey: Keys.hotKey).flatMap { try? JSONDecoder().decode(HotKeyConfiguration.self, from: $0) }) ?? .default
        let savedGIFHotKey = (UserDefaults.standard.data(forKey: Keys.gifHotKey).flatMap { try? JSONDecoder().decode(HotKeyConfiguration.self, from: $0) }) ?? .gifDefault
        let savedStackStartHotKey = UserDefaults.standard.data(forKey: Keys.stackStartHotKey)
            .flatMap { try? JSONDecoder().decode(HotKeyConfiguration.self, from: $0) }
        let savedStackNextHotKey = UserDefaults.standard.data(forKey: Keys.stackNextHotKey)
            .flatMap { try? JSONDecoder().decode(HotKeyConfiguration.self, from: $0) }
        let savedIgnoredBundleIdentifiers = Set(UserDefaults.standard.stringArray(forKey: Keys.ignoredBundleIdentifiers) ?? [])
        let savedAppearance = UserDefaults.standard.string(forKey: Keys.appearance)
            .flatMap(ClipboardAppearance.init(rawValue:)) ?? .system
        let savedMaterial = UserDefaults.standard.string(forKey: Keys.material)
            .flatMap(ClipboardMaterial.init(rawValue:)) ?? .liquidGlass
        hotKey = savedHotKey
        oldHotKey = savedHotKey
        gifHotKey = savedGIFHotKey
        oldGIFHotKey = savedGIFHotKey
        stackStartHotKey = savedStackStartHotKey
        oldStackStartHotKey = savedStackStartHotKey
        stackNextHotKey = savedStackNextHotKey
        oldStackNextHotKey = savedStackNextHotKey
        historyLimit = store.limit
        retention = savedRetention
        ignoredBundleIdentifiers = savedIgnoredBundleIdentifiers
        appearance = savedAppearance
        material = savedMaterial
        launchAtLogin = SMAppService.mainApp.status == .enabled

        hotKeyManager.onHotKey = { [weak self] in
            self?.showPanel()
        }
        gifHotKeyManager.onHotKey = { [weak self] in
            self?.toggleGIFRecording()
        }
        stackStartHotKeyManager.onHotKey = { [weak self] in
            self?.startClipboardStack()
        }
        stackNextHotKeyManager.onHotKey = { [weak self] in
            self?.pasteNextStackItem()
        }
        monitor.ignoredBundleIdentifiers = savedIgnoredBundleIdentifiers
        monitor.onSnapshot = { [weak self] snapshot, sourceApplication in
            guard let self else { return }
            self.store.ingest(snapshot, sourceApplication: sourceApplication)
            guard self.isCapturingStack,
                  let item = self.store.items.first(where: { $0.fingerprint == snapshot.fingerprint })
            else { return }
            self.clipboardStack.append(item.id)
        }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        refreshAvailableApplications()
        monitor.ignoredBundleIdentifiers = ignoredBundleIdentifiers
        monitor.start()
        oldHotKey = hotKey
        oldGIFHotKey = gifHotKey
        oldStackStartHotKey = stackStartHotKey
        oldStackNextHotKey = stackNextHotKey
        if !hotKeyManager.register(hotKey) {
            statusMessage = "Could not register \(hotKey.displayString)."
        }
        if !gifHotKeyManager.register(gifHotKey) {
            statusMessage = "Could not register \(gifHotKey.displayString) for GIF recording."
        }
        _ = stackStartHotKeyManager.register(stackStartHotKey)
        _ = stackNextHotKeyManager.register(stackNextHotKey)
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isAccessibilityTrusted = AXIsProcessTrusted()
                self?.refreshPauseState()
            }
        }
    }

    func stop() {
        monitor.stop()
        hotKeyManager.stop()
        gifHotKeyManager.stop()
        stackStartHotKeyManager.stop()
        stackNextHotKeyManager.stop()
        screenGIFRecorder.cancel()
        annotationEditorController.close()
        quickLookPreview.close()
        favoritesWindow?.orderOut(nil)
        isCapturingStack = false
        clipboardStack.removeAll()
        accessibilityTimer?.invalidate()
        accessibilityTimer = nil
        stopRecordingHotKey()
    }

    func showPanel() {
        quickLookPreview.close()
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
            onPreview: { [weak self] item in self?.preview(item) },
            onEdit: { [weak self] item in self?.editImage(item) },
            onExtractText: { [weak self] item in self?.extractText(item) },
            onSaveGIF: { [weak self] item in self?.saveGIF(item) },
            onSaveFavorite: { [weak self] item in self?.saveAsFavorite(item) },
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

    func extractText(_ item: ClipboardItem) {
        guard item.canExtractText, let imageData = item.imageData else {
            statusMessage = "Text extraction is available for static images only."
            return
        }

        panelController.close()
        statusMessage = "Extracting text…"
        let storedOCRText = item.ocrText

        Task { [weak self] in
            let recognizedText: String?
            if let storedOCRText {
                recognizedText = storedOCRText
            } else {
                recognizedText = await Task.detached(priority: .userInitiated) {
                    LocalOCRService.recognize(imageData: imageData)
                }.value
            }

            guard let self else { return }
            guard let recognizedText, !recognizedText.isEmpty else {
                self.statusMessage = "No text was detected in the image."
                return
            }

            self.copyExtractedText(recognizedText, sourceApplication: item.sourceApplication)
        }
    }

    private func copyExtractedText(_ text: String, sourceApplication: ClipboardSourceApplication? = nil) {
        let pasteboard = NSPasteboard.general
        monitor.suppressCapture()
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            statusMessage = "The extracted text could not be copied."
            return
        }

        store.ingest(ClipboardSnapshot(
            text: text,
            richTextData: nil,
            imageData: nil,
            imageType: nil,
            fileURLs: []
        ), sourceApplication: sourceApplication)
        statusMessage = "Extracted text copied to the clipboard."
    }

    func preview(_ item: ClipboardItem) {
        panelController.close()
        guard quickLookPreview.show(item: item) else {
            statusMessage = "No preview is available for this item."
            return
        }
        statusMessage = nil
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

    func saveAsFavorite(_ item: ClipboardItem) {
        guard let text = item.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusMessage = "Only text items can be saved to the Library."
            return
        }
        _ = snippetStore.add(text: text)
        statusMessage = "Saved to Library."
    }

    func showFavorites() {
        panelController.close()
        targetApplication = panelController.targetApplication(
            excluding: NSRunningApplication.current.processIdentifier
        )

        if favoritesWindow == nil {
            let favoritesSize = NSSize(width: 520, height: 430)
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: favoritesSize),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.appearance = appearance.nsAppearance
            window.setContentSize(favoritesSize)
            window.minSize = NSSize(width: 420, height: 320)
            window.title = "Library — clipboard"
            window.titlebarAppearsTransparent = false
            window.titleVisibility = .visible
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.hidesOnDeactivate = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let rootView = FavoritesView(
                store: snippetStore,
                material: material,
                onPaste: { [weak self] snippet in self?.pasteSnippet(snippet) },
                onClose: { [weak self] in self?.favoritesWindow?.orderOut(nil) }
            )
            let hostingController = NSHostingController(rootView: rootView)
            hostingController.view.frame = NSRect(origin: .zero, size: favoritesSize)
            hostingController.view.autoresizingMask = [.width, .height]
            window.contentViewController = hostingController

            window.center()
            favoritesWindow = window
        }

        applyAppearance(appearance, to: favoritesWindow)
        favoritesWindow?.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        favoritesWindow?.orderFrontRegardless()
        favoritesWindow?.makeKey()
    }

    func showSettings() {
        panelController.close()
        refreshAvailableApplications()

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

    func pauseHistory(for duration: ClipboardPauseDuration) {
        monitor.pauseHistory(for: duration)
        isHistoryPaused = true
        statusMessage = "History capture paused."
    }

    func resumeHistory() {
        monitor.resumeHistory()
        isHistoryPaused = false
        statusMessage = "History capture resumed."
    }

    func refreshPauseState() {
        guard isHistoryPaused else { return }
        if !monitor.isPaused {
            isHistoryPaused = false
            statusMessage = "History capture resumed."
        }
    }

    func refreshAvailableApplications() {
        let currentProcessIdentifier = NSRunningApplication.current.processIdentifier
        var applications = NSWorkspace.shared.runningApplications
            .filter {
                $0.processIdentifier != currentProcessIdentifier &&
                $0.activationPolicy == .regular &&
                $0.bundleIdentifier != nil
            }
            .compactMap { application -> ClipboardApplication? in
                guard let bundleIdentifier = application.bundleIdentifier else { return nil }
                return ClipboardApplication(
                    bundleIdentifier: bundleIdentifier,
                    displayName: application.localizedName ?? bundleIdentifier
                )
            }

        let knownBundleIdentifiers = Set(applications.map(\.bundleIdentifier))
        applications.append(contentsOf: ignoredBundleIdentifiers
            .subtracting(knownBundleIdentifiers)
            .map { ClipboardApplication(bundleIdentifier: $0, displayName: $0) })
        availableApplications = applications.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    func isApplicationIgnored(_ bundleIdentifier: String) -> Bool {
        ignoredBundleIdentifiers.contains(bundleIdentifier)
    }

    func setApplicationIgnored(_ bundleIdentifier: String, ignored: Bool) {
        var updated = ignoredBundleIdentifiers
        if ignored {
            updated.insert(bundleIdentifier)
        } else {
            updated.remove(bundleIdentifier)
        }
        ignoredBundleIdentifiers = updated
    }

    func startClipboardStack() {
        clipboardStack.removeAll()
        targetApplication = nil
        isCapturingStack = true
        statusMessage = "Stack capture started. Copy the items you want to paste in sequence."
    }

    func finishClipboardStack() {
        isCapturingStack = false
        if clipboardStack.isEmpty {
            statusMessage = "Stack capture finished without items."
        } else {
            let suffix = clipboardStack.count == 1 ? "" : "s"
            statusMessage = "Stack ready: \(clipboardStack.count) item\(suffix) queued."
        }
    }

    func cancelClipboardStack() {
        isCapturingStack = false
        clipboardStack.removeAll()
        targetApplication = nil
        statusMessage = "Stack cleared."
    }

    func clearClipboardStack() {
        clipboardStack.removeAll()
        targetApplication = nil
        statusMessage = "Stack cleared."
    }

    func pasteNextStackItem() {
        guard !isCapturingStack else {
            statusMessage = "Finish stack capture before pasting."
            return
        }

        while let firstID = clipboardStack.itemIDs.first,
              store.item(withID: firstID) == nil {
            _ = clipboardStack.removeFirst()
        }

        guard let firstID = clipboardStack.itemIDs.first,
              let item = store.item(withID: firstID)
        else {
            targetApplication = nil
            statusMessage = "The clipboard stack is empty."
            return
        }

        let currentProcessIdentifier = NSRunningApplication.current.processIdentifier
        targetApplication = panelController.targetApplication(excluding: currentProcessIdentifier) ?? targetApplication
        let canPasteAutomatically = AXIsProcessTrusted() && targetApplication != nil
        guard paste(item, targetApplicationOverride: targetApplication) else { return }
        _ = clipboardStack.removeFirst()

        if clipboardStack.isEmpty {
            targetApplication = nil
            statusMessage = canPasteAutomatically
                ? "Last stack item pasted."
                : "Last stack item is on the clipboard. Press ⌘V to paste."
        } else {
            statusMessage = canPasteAutomatically
                ? "Stack item pasted. (\(clipboardStack.count)) remaining."
                : "Stack item ready on the clipboard. Press ⌘V, then paste the next item."
        }
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
        let prompt: String
        switch target {
        case .history: prompt = "Press a new history combination…"
        case .gif: prompt = "Press a new GIF combination…"
        case .stackStart: prompt = "Press a new stack start combination…"
        case .stackNext: prompt = "Press a new paste next combination…"
        }
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
            guard !self.isHotKeyInUse(candidate, excluding: target) else {
                self.statusMessage = "That hotkey is already in use."
                return nil
            }
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
            case .stackStart:
                registered = self.stackStartHotKeyManager.register(candidate)
                if registered {
                    self.oldStackStartHotKey = self.stackStartHotKey
                    self.stackStartHotKey = candidate
                }
            case .stackNext:
                registered = self.stackNextHotKeyManager.register(candidate)
                if registered {
                    self.oldStackNextHotKey = self.stackNextHotKey
                    self.stackNextHotKey = candidate
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

    func clearHotKey(for target: HotKeyTarget) {
        switch target {
        case .stackStart:
            stackStartHotKey = nil
            statusMessage = "Stack start hotkey cleared."
        case .stackNext:
            stackNextHotKey = nil
            statusMessage = "Paste next hotkey cleared."
        case .history, .gif:
            break
        }
    }

    private func persistOptionalHotKey(_ configuration: HotKeyConfiguration?, key: String) {
        guard let configuration else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        UserDefaults.standard.set(try? JSONEncoder().encode(configuration), forKey: key)
    }

    private func isHotKeyInUse(_ candidate: HotKeyConfiguration?, excluding target: HotKeyTarget) -> Bool {
        guard let candidate else { return false }
        let configured: [(HotKeyTarget, HotKeyConfiguration?)] = [
            (.history, hotKey),
            (.gif, gifHotKey),
            (.stackStart, stackStartHotKey),
            (.stackNext, stackNextHotKey)
        ]
        return configured.contains { configuredTarget, configuration in
            configuredTarget != target && configuration == candidate
        }
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

    func saveLatestGIF() {
        guard let item = store.items.first(where: { $0.isGIF }) else {
            statusMessage = "No GIF is available to save."
            return
        }
        saveGIF(item)
    }

    func saveGIF(_ item: ClipboardItem) {
        guard item.isGIF, let data = item.imageData else {
            statusMessage = "This item is not a GIF."
            return
        }

        panelController.close()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.gif]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = GIFFileExporter.defaultFilename()
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let outputURL = try GIFFileExporter.write(data, to: url)
                self?.statusMessage = "GIF saved to \(outputURL.lastPathComponent)."
            } catch {
                self?.statusMessage = "The GIF could not be saved."
            }
        }
    }

    private func pasteSnippet(_ snippet: ClipboardSnippet) {
        favoritesWindow?.orderOut(nil)
        let item = ClipboardItem(
            fingerprint: "snippet-\(snippet.id.uuidString)",
            text: snippet.text,
            richTextData: nil,
            imageData: nil,
            imageType: nil,
            files: []
        )
        _ = paste(item, targetApplicationOverride: targetApplication)
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

    @discardableResult
    private func paste(
        _ item: ClipboardItem,
        format: ClipboardPasteFormat = .original,
        targetApplicationOverride: NSRunningApplication? = nil
    ) -> Bool {
        guard let payload = ClipboardPasteFormatter.payload(for: item, format: format) else {
            statusMessage = "\(format.title) is unavailable for this item."
            return false
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

        guard let destination = targetApplicationOverride ?? targetApplication else {
            statusMessage = "Item restored to the clipboard. Press ⌘V to paste."
            return true
        }
        guard AXIsProcessTrusted() else {
            statusMessage = "Enable Accessibility for automatic paste."
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            return true
        }

        destination.activate(options: [])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            let source = CGEventSource(stateID: .hidSystemState)
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
            keyDown?.flags = .maskCommand
            keyUp?.flags = .maskCommand
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        }
        return true
    }
}
