import AppKit
import Foundation

struct Configuration {
    let outputDirectory: URL
    let iconURL: URL
    let frameCount: Int
}

let arguments = CommandLine.arguments

func argumentValue(_ name: String, default defaultValue: String? = nil) -> String? {
    guard let index = arguments.firstIndex(of: name), arguments.index(after: index) < arguments.endIndex else {
        return defaultValue
    }
    return arguments[arguments.index(after: index)]
}

guard let outputPath = argumentValue("--output"),
      let iconPath = argumentValue("--icon") else {
    fputs("Usage: MakeDemoGIF.swift --output <frames-directory> --icon <icon-path> [--frames <count>]\n", stderr)
    exit(2)
}

let configuration = Configuration(
    outputDirectory: URL(fileURLWithPath: outputPath, isDirectory: true),
    iconURL: URL(fileURLWithPath: iconPath),
    frameCount: Int(argumentValue("--frames", default: "48") ?? "48") ?? 48
)

try FileManager.default.createDirectory(at: configuration.outputDirectory, withIntermediateDirectories: true)

let icon = NSImage(contentsOf: configuration.iconURL)
let canvasSize = NSSize(width: 960, height: 600)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
}

func drawText(_ text: String, in rect: NSRect, font: NSFont, color: NSColor, alignment: NSTextAlignment = .left) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byTruncatingTail
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]
    NSString(string: text).draw(in: rect, withAttributes: attributes)
}

func rounded(_ rect: NSRect, radius: CGFloat, fill: NSColor, stroke: NSColor? = nil, lineWidth: CGFloat = 1) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    fill.setFill()
    path.fill()
    if let stroke {
        stroke.setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }
}

func drawPin(in rect: NSRect, color: NSColor) {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: rect.midX, y: rect.minY + 4))
    path.line(to: NSPoint(x: rect.midX, y: rect.maxY - 10))
    path.move(to: NSPoint(x: rect.minX + 5, y: rect.maxY - 9))
    path.line(to: NSPoint(x: rect.maxX - 5, y: rect.maxY - 9))
    path.move(to: NSPoint(x: rect.minX + 7, y: rect.maxY - 9))
    path.line(to: NSPoint(x: rect.midX, y: rect.maxY - 1))
    path.line(to: NSPoint(x: rect.maxX - 7, y: rect.maxY - 9))
    color.setStroke()
    path.lineWidth = 2
    path.lineCapStyle = .round
    path.stroke()
}

func drawThumbnail(in rect: NSRect, index: Int) {
    NSGraphicsContext.saveGraphicsState()
    let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
    path.addClip()
    let gradientColors: [NSColor]
    switch index {
    case 0:
        gradientColors = [color(0.05, 0.22, 0.46), color(0.04, 0.08, 0.16)]
    case 1:
        gradientColors = [color(0.16, 0.20, 0.32), color(0.08, 0.10, 0.16)]
    default:
        gradientColors = [color(0.18, 0.14, 0.32), color(0.06, 0.07, 0.13)]
    }
    NSGradient(colors: gradientColors)?.draw(in: rect, angle: -25)
    for line in 0..<3 {
        let lineRect = NSRect(x: rect.minX + 10, y: rect.minY + 13 + CGFloat(line * 12), width: rect.width - CGFloat(20 + line * 12), height: 3)
        rounded(lineRect, radius: 1.5, fill: color(0.25, 0.75, 1, 0.75))
    }
    NSGraphicsContext.restoreGraphicsState()
}

func ease(_ value: CGFloat) -> CGFloat {
    let clamped = min(max(value, 0), 1)
    return clamped * clamped * (3 - 2 * clamped)
}

for frame in 0..<configuration.frameCount {
    let image = NSImage(size: canvasSize)
    image.lockFocusFlipped(true)

    let canvas = NSRect(origin: .zero, size: canvasSize)
    NSGradient(colors: [color(0.015, 0.025, 0.07), color(0.06, 0.025, 0.13)])?.draw(in: canvas, angle: 90)

    NSGraphicsContext.saveGraphicsState()
    color(0.10, 0.42, 0.90, 0.10).setFill()
    NSBezierPath(ovalIn: NSRect(x: -120, y: 260, width: 430, height: 430)).fill()
    color(0.60, 0.22, 0.95, 0.08).setFill()
    NSBezierPath(ovalIn: NSRect(x: 690, y: -160, width: 480, height: 480)).fill()
    NSGraphicsContext.restoreGraphicsState()

    color(0.01, 0.015, 0.04, 0.78).setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: canvasSize.width, height: 34)).fill()
    drawText("clipboard", in: NSRect(x: 26, y: 7, width: 130, height: 20), font: .systemFont(ofSize: 13, weight: .semibold), color: color(0.92, 0.96, 1))
    drawText("⌘⇧V", in: NSRect(x: 850, y: 7, width: 80, height: 20), font: .monospacedSystemFont(ofSize: 12, weight: .medium), color: color(0.55, 0.75, 0.95), alignment: .right)

    if let icon {
        icon.draw(in: NSRect(x: 34, y: 61, width: 54, height: 54), from: .zero, operation: .sourceOver, fraction: 1)
    }
    drawText("Clipboard history", in: NSRect(x: 104, y: 66, width: 390, height: 34), font: .systemFont(ofSize: 28, weight: .bold), color: color(0.96, 0.98, 1))
    drawText("Private, local, and ready when you need it.", in: NSRect(x: 106, y: 101, width: 480, height: 22), font: .systemFont(ofSize: 14), color: color(0.64, 0.72, 0.86))

    let entrance = ease(CGFloat(frame) / 9)
    let panelWidth: CGFloat = 500
    let panelHeight: CGFloat = 378
    let panelX = canvasSize.width - panelWidth - 60
    let panelY = 150 + (1 - entrance) * 74
    let panelRect = NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = 34
    shadow.shadowOffset = NSSize(width: 0, height: 12)
    shadow.shadowColor = color(0, 0, 0, 0.42)
    shadow.set()
    rounded(panelRect, radius: 27, fill: color(0.07, 0.08, 0.11, 0.94), stroke: color(0.60, 0.72, 0.90, 0.32), lineWidth: 1)
    NSGraphicsContext.restoreGraphicsState()

    let headerY = panelY + 22
    drawText("clipboard", in: NSRect(x: panelX + 28, y: headerY, width: 170, height: 27), font: .systemFont(ofSize: 19, weight: .bold), color: color(0.95, 0.98, 1))
    drawText("5", in: NSRect(x: panelX + panelWidth - 76, y: headerY + 1, width: 28, height: 24), font: .systemFont(ofSize: 16, weight: .medium), color: color(0.62, 0.73, 0.88), alignment: .right)
    rounded(NSRect(x: panelX + panelWidth - 42, y: headerY - 2, width: 22, height: 22), radius: 11, fill: color(1, 1, 1, 0.08))
    drawText("×", in: NSRect(x: panelX + panelWidth - 39, y: headerY - 3, width: 16, height: 22), font: .systemFont(ofSize: 18, weight: .regular), color: color(0.78, 0.84, 0.94), alignment: .center)

    let rowTop = panelY + 74
    let rowHeight: CGFloat = 78
    let rowGap: CGFloat = 10
    let selectedIndex: Int = frame < 25 ? 0 : (frame < 37 ? 1 : 0)
    let rows = [
        ("https://github.com/Kelsiito/clipboard", "Text"),
        ("Meeting notes — tomorrow at 10:00", "Text"),
        ("Copied image", "Image")
    ]
    for index in rows.indices {
        let y = rowTop + CGFloat(index) * (rowHeight + rowGap)
        let rowRect = NSRect(x: panelX + 18, y: y, width: panelWidth - 36, height: rowHeight)
        let isSelected = entrance > 0.9 && index == selectedIndex && frame > 10
        let fill = isSelected ? color(0.08, 0.15, 0.25, 0.72) : color(1, 1, 1, 0.035)
        let stroke = isSelected ? color(0.16, 0.72, 1, 0.92) : color(1, 1, 1, 0.06)
        rounded(rowRect, radius: 15, fill: fill, stroke: stroke, lineWidth: isSelected ? 1.5 : 1)
        drawThumbnail(in: NSRect(x: rowRect.minX + 12, y: rowRect.minY + 12, width: 54, height: 54), index: index)
        drawText(rows[index].0, in: NSRect(x: rowRect.minX + 80, y: rowRect.minY + 23, width: 280, height: 23), font: .systemFont(ofSize: 15, weight: .medium), color: color(0.94, 0.97, 1))
        drawText(rows[index].1, in: NSRect(x: rowRect.minX + 80, y: rowRect.minY + 47, width: 170, height: 18), font: .systemFont(ofSize: 12), color: color(0.58, 0.68, 0.82))
        drawPin(in: NSRect(x: rowRect.maxX - 42, y: rowRect.minY + 22, width: 22, height: 32), color: isSelected ? color(0.35, 0.82, 1) : color(0.55, 0.65, 0.78))
    }

    let footerY = panelY + panelHeight - 37
    rounded(NSRect(x: panelX + 20, y: footerY, width: 66, height: 25), radius: 8, fill: color(0.16, 0.39, 0.68, 0.32), stroke: color(0.25, 0.73, 1, 0.40))
    drawText("⌘⇧V", in: NSRect(x: panelX + 20, y: footerY + 3, width: 66, height: 18), font: .monospacedSystemFont(ofSize: 12, weight: .semibold), color: color(0.72, 0.91, 1), alignment: .center)
    drawText("Choose and paste", in: NSRect(x: panelX + 98, y: footerY + 3, width: 180, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: color(0.56, 0.66, 0.80))

    if frame >= 39 && frame <= 44 {
        let toastAlpha = min(CGFloat(frame - 38) / 3, CGFloat(44 - frame) / 3)
        rounded(NSRect(x: panelX + 300, y: footerY - 2, width: 142, height: 30), radius: 15, fill: color(0.12, 0.69, 0.76, max(0, toastAlpha) * 0.22), stroke: color(0.25, 0.90, 0.96, max(0, toastAlpha) * 0.62))
        drawText("Pasted", in: NSRect(x: panelX + 300, y: footerY + 4, width: 142, height: 17), font: .systemFont(ofSize: 12, weight: .semibold), color: color(0.66, 0.98, 1, max(0, toastAlpha)), alignment: .center)
    }

    let outputURL = configuration.outputDirectory.appendingPathComponent(String(format: "frame-%03d.png", frame))
    image.unlockFocus()
    var proposedRect = NSRect(origin: .zero, size: canvasSize)
    guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil),
          let png = NSBitmapImageRep(cgImage: cgImage).representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else {
        fputs("Could not encode frame \(frame)\n", stderr)
        exit(1)
    }
    try png.write(to: outputURL)
}
