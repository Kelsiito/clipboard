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
        onSelect: @escaping (ClipboardItem) -> Void,
        onTogglePin: @escaping (ClipboardItem) -> Void
    ) {
        // Resolve the caret before creating or activating any clipboard UI so focus
        // still belongs to the app where the user intends to paste.
        let anchor = textAnchor(for: targetApplication)
            ?? windowAnchor(for: targetApplication)
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.contentViewController = NSHostingController(
            rootView: ClipboardPanelView(
                store: store,
                onSelect: onSelect,
                onTogglePin: onTogglePin,
                onClose: { [weak self] in self?.close() }
            )
        )
        panel.setContentSize(pickerSize)
        positionPanel(panel, anchor: anchor)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()
    }

    func close() {
        panel?.orderOut(nil)
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
        guard let focusedElement = focusedElement(for: applicationElement),
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
        var editableValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element,
            "AXEditable" as CFString,
            &editableValue
        ) == .success,
           let isEditable = editableValue as? Bool,
           isEditable {
            return true
        }

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

    private func windowAnchor(for application: NSRunningApplication?) -> TextAnchor? {
        guard let application else { return nil }

        let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]]

        guard let window = windows?.first(where: { info in
            let ownerPID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue
            return ownerPID == application.processIdentifier && layer == 0
        }),
        let bounds = window[kCGWindowBounds as String] as? NSDictionary,
        let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
        rect.width > 1,
        rect.height > 1
        else {
            return nil
        }

        return anchor(for: rect)
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
    let onSelect: (ClipboardItem) -> Void
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
                ContentUnavailableView("Histórico vazio", systemImage: "doc.on.clipboard")
                    .frame(maxWidth: .infinity, minHeight: visibleListHeight)
            } else {
                List(items) { item in
                    ClipboardRow(
                        item: item,
                        isSelected: selectedID == item.id,
                        onTogglePin: { onTogglePin(item) }
                    )
                        .contextMenu {
                            Button(item.isPinned ? "Desafixar" : "Afixar") { onTogglePin(item) }
                            Divider()
                            Button("Colar") { onSelect(item) }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(item) }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
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
        .clipboardGlassSurface(in: panelShape)
        .overlay {
            panelShape.stroke(.white.opacity(0.16), lineWidth: 0.5)
        }
        .opacity(isPresented ? 1 : 0)
        .scaleEffect(isPresented ? 1 : 0.94, anchor: .bottom)
        .offset(y: isPresented ? 0 : 26)
        .clipboardGlassEntranceTransition()
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
        if #available(macOS 26.0, *) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Fechar")
        } else {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fechar")
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
        onSelect(item)
    }
}

private struct ClipboardRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    let onTogglePin: () -> Void

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
            Button(action: onTogglePin) {
                Image(systemName: item.isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(item.isPinned ? .cyan : .secondary)
                    .frame(width: 28, height: 28)
            }
            .clipboardGlassButtonStyle()
            .help(item.isPinned ? "Desafixar" : "Afixar")
        }
        .padding(.vertical, 4)
        .frame(height: 64)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.88) : .clear)
        }
    }

    private var iconName: String {
        if item.hasFiles { return "doc.on.doc" }
        if item.hasImage { return "photo" }
        return "text.alignleft"
    }
}
