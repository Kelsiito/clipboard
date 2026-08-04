import ApplicationServices
import AppKit
import SwiftUI

private final class ClipboardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        if isVisible { orderOut(nil) }
    }
}

enum ClipboardPanelPlacement {
    static func composerAnchor(in window: CGRect, bottomInset: CGFloat = 96) -> CGRect {
        let y = max(window.minY, window.maxY - max(bottomInset, 0))
        return CGRect(x: window.midX - 0.5, y: y, width: 1, height: 1)
    }

    static func origin(
        anchor: NSRect,
        panelSize: NSSize,
        visibleFrame: NSRect,
        margin: CGFloat = 12
    ) -> NSPoint {
        let minimumX = visibleFrame.minX + margin
        let maximumX = max(minimumX, visibleFrame.maxX - panelSize.width - margin)
        let originX = min(max(anchor.midX - panelSize.width / 2, minimumX), maximumX)

        var originY = anchor.maxY + margin
        if originY + panelSize.height > visibleFrame.maxY - margin {
            originY = anchor.minY - panelSize.height - margin
        }
        let minimumY = visibleFrame.minY + margin
        let maximumY = max(minimumY, visibleFrame.maxY - panelSize.height - margin)
        originY = min(max(originY, minimumY), maximumY)

        return NSPoint(x: originX, y: originY)
    }
}

@MainActor
final class ClipboardPanelController {
    private var panel: ClipboardPanel?
    private let pickerSize = NSSize(width: 460, height: 300)

    func targetApplication(excluding processIdentifier: pid_t) -> NSRunningApplication? {
        if AXIsProcessTrusted(), let focusedApplication = focusedApplicationElement() {
            var focusedProcessIdentifier: pid_t = 0
            if AXUIElementGetPid(focusedApplication, &focusedProcessIdentifier) == .success,
               focusedProcessIdentifier != processIdentifier,
               let application = NSRunningApplication(processIdentifier: focusedProcessIdentifier) {
                return application
            }
        }

        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication,
              frontmostApplication.processIdentifier != processIdentifier
        else {
            return nil
        }
        return frontmostApplication
    }

    func show(
        store: ClipboardStore,
        targetApplication: NSRunningApplication?,
        appearance: ClipboardAppearance,
        material: ClipboardMaterial,
        onPaste: @escaping (ClipboardItem, ClipboardPasteFormat) -> Void,
        onTogglePin: @escaping (ClipboardItem) -> Void
    ) {
        // Resolve the caret before creating or activating any clipboard UI so focus
        // still belongs to the app where the user intends to paste.
        let textPosition = textAnchor(for: targetApplication)
        let fallbackPosition = textPosition == nil ? fallbackAnchor(for: targetApplication) : nil
        let anchor = textPosition ?? fallbackPosition
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.appearance = appearance.nsAppearance
        panel.contentViewController = NSHostingController(
            rootView: ClipboardPanelView(
                store: store,
                material: material,
                onPaste: onPaste,
                onTogglePin: onTogglePin,
                onClose: { [weak self] in self?.close() }
            )
        )
        panel.contentView?.appearance = appearance.nsAppearance
        panel.setContentSize(pickerSize)
        positionPanel(panel, anchor: anchor)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()
    }

    func close() {
        panel?.orderOut(nil)
    }

    func setAppearance(_ appearance: ClipboardAppearance) {
        panel?.appearance = appearance.nsAppearance
        panel?.contentView?.appearance = appearance.nsAppearance
    }

    private func makePanel() -> ClipboardPanel {
        let panel = ClipboardPanel(
            contentRect: NSRect(origin: .zero, size: pickerSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }

    private func positionPanel(_ panel: NSPanel, anchor: TextAnchor?) {
        guard let anchor else {
            panel.center()
            return
        }

        let screen = anchor.screen
        let selection = anchor.rect
        let visibleFrame = screen.visibleFrame
        let panelSize = pickerSize
        panel.setFrameOrigin(
            ClipboardPanelPlacement.origin(
                anchor: selection,
                panelSize: panelSize,
                visibleFrame: visibleFrame
            )
        )
    }

    private struct TextAnchor {
        let screen: NSScreen
        let rect: NSRect
    }

    private func textAnchor(for application: NSRunningApplication?) -> TextAnchor? {
        guard AXIsProcessTrusted(), let application else { return nil }

        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        guard let focusedElement = focusedTextElement(
            for: applicationElement,
            processIdentifier: application.processIdentifier
        ),
              isEditableTextElement(focusedElement)
        else { return nil }

        var selectedRangeValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRangeValue
        ) == .success,
           let selectedRangeValue,
           let rangeForCaret = caretRange(from: selectedRangeValue) {
            if let caretBounds = bounds(of: focusedElement, for: rangeForCaret) {
                return anchor(for: caretBounds)
            }
            if let selectionBounds = bounds(of: focusedElement, for: selectedRangeValue) {
                return anchor(for: selectionBounds)
            }
        }

        if let focusedFrame = frame(of: focusedElement) {
            return anchor(for: focusedFrame)
        }

        return nil
    }

    private func anchor(for accessibilityRect: CGRect) -> TextAnchor? {
        let rect = CGRect(
            x: accessibilityRect.minX,
            y: accessibilityRect.minY,
            width: max(accessibilityRect.width, 1),
            height: max(accessibilityRect.height, 1)
        )

        let accessibilityCenter = CGPoint(x: rect.midX, y: rect.midY)
        for screen in NSScreen.screens {
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                continue
            }
            let displayBounds = CGDisplayBounds(CGDirectDisplayID(screenNumber.uint32Value))
            guard displayBounds.contains(accessibilityCenter) else { continue }

            let cocoaRect = NSRect(
                x: screen.frame.minX + rect.minX - displayBounds.minX,
                y: screen.frame.maxY - (rect.maxY - displayBounds.minY),
                width: rect.width,
                height: rect.height
            )
            return TextAnchor(screen: screen, rect: cocoaRect)
        }

        return nil
    }

    private func focusedElement(for applicationElement: AXUIElement) -> AXUIElement? {
        var focusedValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                applicationElement,
                kAXFocusedUIElementAttribute as CFString,
                &focusedValue
            ) == .success,
            let focusedValue
        else {
            return nil
        }
        return (focusedValue as! AXUIElement)
    }

    private func focusedElement(
        for applicationElement: AXUIElement,
        processIdentifier: pid_t
    ) -> AXUIElement? {
        if let applicationFocusedElement = focusedElement(for: applicationElement) {
            return applicationFocusedElement
        }

        guard let systemFocusedElement = systemWideFocusedElement()
        else { return nil }

        var focusedProcessIdentifier: pid_t = 0
        guard AXUIElementGetPid(systemFocusedElement, &focusedProcessIdentifier) == .success,
              focusedProcessIdentifier == processIdentifier
        else { return nil }
        return systemFocusedElement
    }

    private func focusedTextElement(
        for applicationElement: AXUIElement,
        processIdentifier: pid_t
    ) -> AXUIElement? {
        if let focusedElement = focusedElement(
            for: applicationElement,
            processIdentifier: processIdentifier
        ), isEditableTextElement(focusedElement) {
            return focusedElement
        }

        var focusedWindowValue: CFTypeRef?
        let focusedWindowResult = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowValue
        )

        if focusedWindowResult == .success, let focusedWindowValue {
            var visited = Set<CFHashCode>()
            if let match = findEditableTextElement(
                in: focusedWindowValue as! AXUIElement,
                depth: 0,
                visited: &visited
            ) {
                return match
            }
        }

        if let systemFocusedElement = systemWideFocusedElement() {
            var focusedProcessIdentifier: pid_t = 0
            guard AXUIElementGetPid(systemFocusedElement, &focusedProcessIdentifier) == .success,
                  focusedProcessIdentifier == processIdentifier
            else { return nil }

            var visited = Set<CFHashCode>()
            return findEditableTextElement(
                in: systemFocusedElement,
                depth: 0,
                visited: &visited
            )
        }
        return nil
    }

    private func findEditableTextElement(
        in element: AXUIElement,
        depth: Int,
        visited: inout Set<CFHashCode>
    ) -> AXUIElement? {
        guard depth < 12, visited.insert(CFHash(element)).inserted else { return nil }

        var focusedValue: CFTypeRef?
        let isFocused = AXUIElementCopyAttributeValue(
            element,
            kAXFocusedAttribute as CFString,
            &focusedValue
        ) == .success && (focusedValue as? Bool == true)

        if isEditableTextElement(element) {
            return element
        }

        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &childrenValue
        ) == .success,
              let children = childrenValue as? [AXUIElement]
        else { return nil }

        let orderedChildren = isFocused ? children : children.reversed()
        for child in orderedChildren {
            if let match = findEditableTextElement(
                in: child,
                depth: depth + 1,
                visited: &visited
            ) {
                return match
            }
        }
        return nil
    }

    private func systemWideFocusedElement() -> AXUIElement? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
              let focusedValue
        else { return nil }
        return (focusedValue as! AXUIElement)
    }

    private func focusedApplicationElement() -> AXUIElement? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedApplicationValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                systemWideElement,
                kAXFocusedApplicationAttribute as CFString,
                &focusedApplicationValue
            ) == .success,
            let focusedApplicationValue
        else {
            return nil
        }
        return (focusedApplicationValue as! AXUIElement)
    }

    private func isEditableTextElement(_ element: AXUIElement) -> Bool {
        var roleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXRoleAttribute as CFString,
            &roleValue
        ) == .success,
              let role = roleValue as? String
        else { return false }

        return role == kAXTextFieldRole as String
            || role == kAXTextAreaRole as String
            || role == kAXComboBoxRole as String
    }

    private func caretRange(from selectedRangeValue: CFTypeRef) -> CFTypeRef? {
        guard CFGetTypeID(selectedRangeValue) == AXValueGetTypeID() else { return nil }
        let rangeValue = selectedRangeValue as! AXValue
        guard AXValueGetType(rangeValue) == .cfRange else { return nil }

        var selectedRange = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &selectedRange) else { return nil }

        var caretRange = CFRange(
            location: selectedRange.location + selectedRange.length,
            length: 0
        )
        return AXValueCreate(.cfRange, &caretRange)
    }

    private func fallbackAnchor(for application: NSRunningApplication?) -> TextAnchor? {
        guard let application, let window = windowBounds(for: application) else { return nil }

        if application.bundleIdentifier == "com.openai.codex" {
            return anchor(for: ClipboardPanelPlacement.composerAnchor(in: window))
        }

        return anchor(for: window)
    }

    private func windowBounds(for application: NSRunningApplication?) -> CGRect? {
        guard let application else { return nil }

        let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]]

        let candidates = windows?.compactMap { info -> CGRect? in
            let ownerPID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue
            guard ownerPID == application.processIdentifier,
                  layer == 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  rect.width > 1,
                  rect.height > 1
            else { return nil }
            return rect
        }

        guard let rect = candidates?.max(by: { lhs, rhs in
            lhs.width * lhs.height < rhs.width * rhs.height
        })
        else {
            return nil
        }

        return rect
    }

    private func bounds(of element: AXUIElement, for range: CFTypeRef) -> CGRect? {
        var boundsValue: CFTypeRef?
        guard
            AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXBoundsForRangeParameterizedAttribute as CFString,
                range,
                &boundsValue
            ) == .success,
            let boundsValue
        else {
            return nil
        }
        let axValue = boundsValue as! AXValue

        var rect = CGRect.zero
        guard AXValueGetValue(axValue, .cgRect, &rect),
              !rect.isNull,
              rect.minX.isFinite,
              rect.minY.isFinite,
              rect.height > 0
        else { return nil }
        return rect
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
            AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
            let positionValue,
            let sizeValue
        else {
            return nil
        }
        let position = positionValue as! AXValue
        let size = sizeValue as! AXValue

        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard
            AXValueGetValue(position, .cgPoint, &point),
            AXValueGetValue(size, .cgSize, &dimensions)
        else {
            return nil
        }
        return CGRect(origin: point, size: dimensions)
    }
}

struct ClipboardPanelView: View {
    @ObservedObject var store: ClipboardStore
    let material: ClipboardMaterial
    let onPaste: (ClipboardItem, ClipboardPasteFormat) -> Void
    let onTogglePin: (ClipboardItem) -> Void
    let onClose: () -> Void

    @State private var selectedID: UUID?
    @State private var isPresented = false
    @FocusState private var isListFocused: Bool

    private let visibleListHeight: CGFloat = 210

    var body: some View {
        let items = store.items
        let panelShape = RoundedRectangle(cornerRadius: 24, style: .continuous)

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "doc.on.clipboard.fill")
                    .foregroundStyle(.cyan)
                Text("clipboard")
                    .font(.headline)
                Spacer()
                Text("\(items.count)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                closeButton
            }

            if items.isEmpty {
                ContentUnavailableView("Empty history", systemImage: "doc.on.clipboard")
                    .frame(maxWidth: .infinity, minHeight: visibleListHeight)
            } else {
                List(items) { item in
                    ClipboardRow(
                        item: item,
                        onPaste: onPaste,
                        onTogglePin: { onTogglePin(item) }
                    )
                        .contextMenu {
                            Button(item.isPinned ? "Unpin" : "Pin") { onTogglePin(item) }
                            Divider()
                            Button("Paste") { onPaste(item, .original) }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { onPaste(item, .original) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .frame(height: visibleListHeight)
                .focused($isListFocused)
                .focusEffectDisabled()
                .onMoveCommand { direction in moveSelection(direction) }
                .onKeyPress(keys: [.upArrow, .downArrow], phases: [.down, .repeat]) { press in
                    switch press.key {
                    case .upArrow:
                        moveSelection(.up)
                    case .downArrow:
                        moveSelection(.down)
                    default:
                        break
                    }
                    return .handled
                }
                .onKeyPress(.return) {
                    submitSelection()
                    return .handled
                }
            }
        }
        .padding(16)
        .frame(width: 460, height: 300, alignment: .top)
        .clipShape(panelShape)
        .clipboardGlassSurface(in: panelShape, material: material)
        .opacity(isPresented ? 1 : 0)
        .scaleEffect(isPresented ? 1 : 0.94, anchor: .bottom)
        .offset(y: isPresented ? 0 : 26)
        .clipboardGlassEntranceTransition(material: material)
        .onAppear {
            selectedID = items.first?.id
            isPresented = false
            DispatchQueue.main.async {
                isListFocused = true
                withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                    isPresented = true
                }
            }
        }
        .onExitCommand(perform: onClose)
    }

    @ViewBuilder
    private var closeButton: some View {
        if material == .liquidGlass, #available(macOS 26.0, *) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Close")
        } else {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        let items = store.items
        guard !items.isEmpty else { return }
        let currentIndex = selectedID.flatMap { id in items.firstIndex { $0.id == id } } ?? 0
        let nextIndex: Int
        switch direction {
        case .up: nextIndex = max(currentIndex - 1, 0)
        case .down: nextIndex = min(currentIndex + 1, items.count - 1)
        default: return
        }
        selectedID = items[nextIndex].id
    }

    private func submitSelection() {
        let items = store.items
        guard let selectedID, let item = items.first(where: { $0.id == selectedID }) else { return }
        onPaste(item, .original)
    }
}

private struct ClipboardRow: View {
    let item: ClipboardItem
    let onPaste: (ClipboardItem, ClipboardPasteFormat) -> Void
    let onTogglePin: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            if let imageData = item.imageData, let nsImage = NSImage(data: imageData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: iconName)
                    .font(.title2)
                    .frame(width: 48, height: 48)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.preview)
                    .lineLimit(2)
                    .font(.body)
                Text(item.kindLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            SmartPasteMenu(item: item, onPaste: onPaste)
            Button(action: onTogglePin) {
                Image(systemName: item.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(item.isPinned ? Color.cyan : Color.primary.opacity(isHovered ? 0.95 : 0.72))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
                    .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
            }
            .buttonStyle(.plain)
            .help(item.isPinned ? "Unpin" : "Pin")
        }
        .padding(.vertical, 4)
        .frame(height: 64)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isHovered ? Color.primary.opacity(0.32) : .clear, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }

    private var iconName: String {
        if item.hasFiles { return "doc.on.doc" }
        if item.hasImage { return "photo" }
        return "text.alignleft"
    }
}

private struct SmartPasteMenu: View {
    let item: ClipboardItem
    let onPaste: (ClipboardItem, ClipboardPasteFormat) -> Void

    var body: some View {
        Menu {
            Section("Paste as") {
                ForEach(ClipboardPasteFormat.available(for: item)) { format in
                    Button {
                        onPaste(item, format)
                    } label: {
                        Label(format.title, systemImage: format.systemImage)
                    }
                }
            }
        } label: {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.cyan)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
                .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .accessibilityLabel("Smart Paste")
        .help("Smart Paste")
    }
}
