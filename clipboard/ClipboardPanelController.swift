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

@MainActor
final class ClipboardPanelController {
    private var panel: ClipboardPanel?

    func show(
        store: ClipboardStore,
        targetApplication: NSRunningApplication?,
        onSelect: @escaping (ClipboardItem) -> Void,
        onTogglePin: @escaping (ClipboardItem) -> Void
    ) {
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
        positionPanel(panel, targetApplication: targetApplication)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> ClipboardPanel {
        let panel = ClipboardPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
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

    private func positionPanel(_ panel: NSPanel, targetApplication: NSRunningApplication?) {
        let anchor = textAnchor(for: targetApplication) ?? mouseAnchor()
        guard let anchor else {
            panel.center()
            return
        }

        let screen = anchor.screen
        let selection = anchor.rect
        let visibleFrame = screen.visibleFrame
        let panelSize = panel.frame.size
        let horizontalMargin: CGFloat = 12
        let verticalMargin: CGFloat = 24

        let minimumX = visibleFrame.minX + horizontalMargin
        let maximumX = max(minimumX, visibleFrame.maxX - panelSize.width - horizontalMargin)
        let originX = min(max(selection.midX - panelSize.width / 2, minimumX), maximumX)

        var originY = selection.maxY + verticalMargin
        if originY + panelSize.height > visibleFrame.maxY - verticalMargin {
            originY = selection.minY - panelSize.height - verticalMargin
        }
        let minimumY = visibleFrame.minY + verticalMargin
        let maximumY = max(minimumY, visibleFrame.maxY - panelSize.height - verticalMargin)
        originY = min(max(originY, minimumY), maximumY)

        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    private struct TextAnchor {
        let screen: NSScreen
        let rect: NSRect
    }

    private func textAnchor(for application: NSRunningApplication?) -> TextAnchor? {
        guard AXIsProcessTrusted(), let application else { return nil }

        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
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
        let focusedElement = focusedValue as! AXUIElement

        var selectedRangeValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRangeValue
        ) == .success,
           let selectedRangeValue,
           let bounds = bounds(of: focusedElement, for: selectedRangeValue) {
            return anchor(for: bounds)
        }

        guard let focusedFrame = frame(of: focusedElement) else { return nil }
        return anchor(for: focusedFrame)
    }

    private func anchor(for accessibilityRect: CGRect) -> TextAnchor? {
        let rect = CGRect(
            x: accessibilityRect.minX,
            y: accessibilityRect.minY,
            width: max(accessibilityRect.width, 1),
            height: max(accessibilityRect.height, 1)
        )

        for screen in NSScreen.screens {
            let cocoaRect = NSRect(
                x: rect.minX,
                y: screen.frame.maxY - rect.maxY,
                width: rect.width,
                height: rect.height
            )
            if screen.frame.contains(NSPoint(x: cocoaRect.midX, y: cocoaRect.midY)) {
                return TextAnchor(screen: screen, rect: cocoaRect)
            }
        }

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }
        let cocoaRect = NSRect(
            x: rect.minX,
            y: screen.frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
        return TextAnchor(screen: screen, rect: cocoaRect)
    }

    private func mouseAnchor() -> TextAnchor? {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main else {
            return nil
        }
        return TextAnchor(screen: screen, rect: NSRect(origin: mouseLocation, size: .zero))
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
        guard AXValueGetValue(axValue, .cgRect, &rect), !rect.isNull else { return nil }
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

    private let visibleListHeight: CGFloat = 198

    var body: some View {
        let items = store.items

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
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Fechar")
            }

            if items.isEmpty {
                ContentUnavailableView("Histórico vazio", systemImage: "doc.on.clipboard")
                    .frame(maxWidth: .infinity, minHeight: visibleListHeight)
            } else {
                List(items, selection: $selectedID) { item in
                    ClipboardRow(item: item, onTogglePin: { onTogglePin(item) })
                        .tag(item.id)
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
                .onMoveCommand { direction in moveSelection(direction) }
                .onSubmit { submitSelection() }
            }
        }
        .padding(16)
        .frame(width: 460, height: 300, alignment: .top)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.12)))
        .opacity(isPresented ? 1 : 0)
        .scaleEffect(isPresented ? 1 : 0.94, anchor: .bottom)
        .offset(y: isPresented ? 0 : 26)
        .onAppear {
            selectedID = items.first?.id
            isPresented = false
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                    isPresented = true
                }
            }
        }
        .onExitCommand(perform: onClose)
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
            .buttonStyle(.borderless)
            .help(item.isPinned ? "Desafixar" : "Afixar")
        }
        .padding(.vertical, 4)
        .frame(height: 64)
    }

    private var iconName: String {
        if item.hasFiles { return "doc.on.doc" }
        if item.hasImage { return "photo" }
        return "text.alignleft"
    }
}
