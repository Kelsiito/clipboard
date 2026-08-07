import AppKit
import SwiftUI

enum AnnotationTool: String, CaseIterable, Identifiable {
    case draw
    case line
    case arrow
    case rectangle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .draw: return "Draw"
        case .line: return "Line"
        case .arrow: return "Arrow"
        case .rectangle: return "Rectangle"
        }
    }

    var systemImage: String {
        switch self {
        case .draw: return "pencil.tip"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        }
    }
}

struct AnnotationPoint: Equatable {
    let x: CGFloat
    let y: CGFloat

    init(_ point: CGPoint, in size: CGSize) {
        x = min(max(point.x / max(size.width, 1), 0), 1)
        y = min(max(point.y / max(size.height, 1), 0), 1)
    }

    func point(in size: CGSize) -> CGPoint {
        CGPoint(x: x * size.width, y: y * size.height)
    }

    func imagePoint(in size: CGSize) -> CGPoint {
        CGPoint(x: x * size.width, y: (1 - y) * size.height)
    }
}

struct AnnotationMark: Identifiable, Equatable {
    let id = UUID()
    let tool: AnnotationTool
    var points: [AnnotationPoint]
}

@MainActor
final class AnnotationDocument: ObservableObject {
    let image: NSImage

    @Published var selectedTool: AnnotationTool = .arrow
    @Published private(set) var marks: [AnnotationMark] = []
    @Published private(set) var currentMark: AnnotationMark?

    init(image: NSImage) {
        self.image = image
    }

    func begin(at point: CGPoint, in size: CGSize) {
        currentMark = AnnotationMark(tool: selectedTool, points: [AnnotationPoint(point, in: size)])
    }

    func update(to point: CGPoint, in size: CGSize) {
        guard var mark = currentMark else { return }
        let nextPoint = AnnotationPoint(point, in: size)
        if mark.tool == .draw {
            mark.points.append(nextPoint)
        } else if mark.points.count == 1 {
            mark.points.append(nextPoint)
        } else {
            mark.points[1] = nextPoint
        }
        currentMark = mark
    }

    func finish() {
        guard let currentMark,
              currentMark.points.count > 1,
              currentMark.points.first != currentMark.points.last else {
            self.currentMark = nil
            return
        }
        marks.append(currentMark)
        self.currentMark = nil
    }

    func undo() {
        _ = marks.popLast()
    }

    func clear() {
        marks.removeAll()
        currentMark = nil
    }

    func renderedPNGData() -> Data? {
        let pixelWidth = image.representations.map(\.pixelsWide).max() ?? Int(image.size.width)
        let pixelHeight = image.representations.map(\.pixelsHigh).max() ?? Int(image.size.height)
        let width = max(pixelWidth, 1)
        let height = max(pixelHeight, 1)
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: representation) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let outputSize = CGSize(width: width, height: height)
        image.draw(in: CGRect(origin: .zero, size: outputSize))
        NSColor.systemRed.setStroke()
        for mark in marks {
            draw(mark, in: outputSize)
        }
        NSGraphicsContext.restoreGraphicsState()
        return representation.representation(using: .png, properties: [:])
    }

    private func draw(_ mark: AnnotationMark, in size: CGSize) {
        guard let first = mark.points.first?.imagePoint(in: size),
              let last = mark.points.last?.imagePoint(in: size) else { return }
        let path = NSBezierPath()
        path.lineWidth = max(size.width * 0.004, 3)
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        switch mark.tool {
        case .draw:
            path.move(to: first)
            for point in mark.points.dropFirst() {
                path.line(to: point.imagePoint(in: size))
            }
        case .line:
            path.move(to: first)
            path.line(to: last)
        case .arrow:
            path.move(to: first)
            path.line(to: last)
            addArrowHead(to: path, from: first, to: last, canvasWidth: size.width)
        case .rectangle:
            path.appendRect(CGRect(
                x: min(first.x, last.x),
                y: min(first.y, last.y),
                width: abs(last.x - first.x),
                height: abs(last.y - first.y)
            ))
        }
        path.stroke()
    }

    private func addArrowHead(to path: NSBezierPath, from start: CGPoint, to end: CGPoint, canvasWidth: CGFloat) {
        let angle = atan2(start.y - end.y, start.x - end.x)
        let length = max(canvasWidth * 0.025, 14)
        for offset in [-CGFloat.pi / 6, CGFloat.pi / 6] {
            path.move(to: end)
            path.line(to: CGPoint(
                x: end.x + cos(angle + offset) * length,
                y: end.y + sin(angle + offset) * length
            ))
        }
    }
}

struct AnnotationEditorView: View {
    @StateObject private var document: AnnotationDocument
    let onCopy: (Data) -> Void
    let onCancel: () -> Void

    init(image: NSImage, onCopy: @escaping (Data) -> Void, onCancel: @escaping () -> Void) {
        _document = StateObject(wrappedValue: AnnotationDocument(image: image))
        self.onCopy = onCopy
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            GeometryReader { proxy in
                let fittedSize = aspectFit(document.image.size, in: proxy.size)
                ZStack {
                    Color(nsColor: .windowBackgroundColor)
                    ZStack {
                        Image(nsImage: document.image)
                            .resizable()
                            .scaledToFit()
                        Canvas { context, size in
                            for mark in document.marks {
                                draw(mark, in: &context, size: size)
                            }
                            if let currentMark = document.currentMark {
                                draw(currentMark, in: &context, size: size)
                            }
                        }
                    }
                    .frame(width: fittedSize.width, height: fittedSize.height)
                    .contentShape(Rectangle())
                    .gesture(drawingGesture(in: fittedSize))
                }
            }
            Divider()
            HStack {
                Text("Draw on the capture, then copy the finished image.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Copy to Clipboard") {
                    if let data = document.renderedPNGData() {
                        onCopy(data)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(14)
        }
        .frame(minWidth: 680, minHeight: 520)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            ForEach(AnnotationTool.allCases) { tool in
                Button {
                    document.selectedTool = tool
                } label: {
                    Label(tool.title, systemImage: tool.systemImage)
                }
                .buttonStyle(.bordered)
                .tint(document.selectedTool == tool ? .accentColor : nil)
            }
            Spacer()
            Button("Undo", systemImage: "arrow.uturn.backward") {
                document.undo()
            }
            .disabled(document.marks.isEmpty)
            Button("Clear", systemImage: "trash") {
                document.clear()
            }
            .disabled(document.marks.isEmpty)
        }
        .padding(12)
    }

    private func drawingGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if document.currentMark == nil {
                    document.begin(at: value.startLocation, in: size)
                }
                document.update(to: value.location, in: size)
            }
            .onEnded { value in
                document.update(to: value.location, in: size)
                document.finish()
            }
    }

    private func draw(_ mark: AnnotationMark, in context: inout GraphicsContext, size: CGSize) {
        guard let first = mark.points.first?.point(in: size),
              let last = mark.points.last?.point(in: size) else { return }
        var path = Path()

        switch mark.tool {
        case .draw:
            path.move(to: first)
            for point in mark.points.dropFirst() {
                path.addLine(to: point.point(in: size))
            }
        case .line:
            path.move(to: first)
            path.addLine(to: last)
        case .arrow:
            path.move(to: first)
            path.addLine(to: last)
            let angle = atan2(first.y - last.y, first.x - last.x)
            let length = max(size.width * 0.025, 12)
            for offset in [-CGFloat.pi / 6, CGFloat.pi / 6] {
                path.move(to: last)
                path.addLine(to: CGPoint(
                    x: last.x + cos(angle + offset) * length,
                    y: last.y + sin(angle + offset) * length
                ))
            }
        case .rectangle:
            path.addRect(CGRect(
                x: min(first.x, last.x),
                y: min(first.y, last.y),
                width: abs(last.x - first.x),
                height: abs(last.y - first.y)
            ))
        }
        context.stroke(path, with: .color(.red), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
    }

    private func aspectFit(_ source: CGSize, in destination: CGSize) -> CGSize {
        guard source.width > 0, source.height > 0 else { return destination }
        let scale = min(destination.width / source.width, destination.height / source.height)
        return CGSize(width: source.width * scale, height: source.height * scale)
    }
}

@MainActor
final class AnnotationEditorController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(
        image: NSImage,
        appearance: ClipboardAppearance,
        onCopy: @escaping (Data) -> Void
    ) {
        close()
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let windowSize = NSSize(
            width: min(max(screenFrame.width * 0.72, 760), 1100),
            height: min(max(screenFrame.height * 0.72, 560), 820)
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Annotate Screenshot"
        window.minSize = NSSize(width: 680, height: 520)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.appearance = appearance.nsAppearance
        window.delegate = self

        let rootView = AnnotationEditorView(
            image: image,
            onCopy: { [weak self] data in
                onCopy(data)
                self?.close()
            },
            onCancel: { [weak self] in self?.close() }
        )
        window.contentViewController = NSHostingController(rootView: rootView)
        window.center()
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
        window = nil
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
