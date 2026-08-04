import AppKit
import Foundation

enum ClipboardPasteFormat: String, CaseIterable, Identifiable {
    case original
    case plainText
    case markdown
    case prettyJSON
    case markdownLink

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "Original"
        case .plainText: return "Plain Text"
        case .markdown: return "Clean Markdown"
        case .prettyJSON: return "Format JSON"
        case .markdownLink: return "Markdown Link"
        }
    }

    var systemImage: String {
        switch self {
        case .original: return "doc.on.clipboard"
        case .plainText: return "textformat"
        case .markdown: return "number"
        case .prettyJSON: return "curlybraces"
        case .markdownLink: return "link"
        }
    }

    static func available(for item: ClipboardItem) -> [ClipboardPasteFormat] {
        var formats: [ClipboardPasteFormat] = [.original]
        guard item.hasText, let text = item.text else { return formats }

        formats.append(.plainText)
        formats.append(.markdown)
        if ClipboardPasteFormatter.prettyPrintedJSON(text) != nil {
            formats.append(.prettyJSON)
        }
        if ClipboardPasteFormatter.markdownLink(text) != nil {
            formats.append(.markdownLink)
        }
        return formats
    }
}

struct ClipboardPastePayload {
    let text: String?
    let richTextData: Data?
    let imageData: Data?
    let imageType: String?
    let fileURLs: [URL]
}

enum ClipboardPasteFormatter {
    static func payload(for item: ClipboardItem, format: ClipboardPasteFormat) -> ClipboardPastePayload? {
        switch format {
        case .original:
            return ClipboardPastePayload(
                text: item.text,
                richTextData: item.richTextData,
                imageData: item.imageData,
                imageType: item.imageType,
                fileURLs: item.files.compactMap(\.resolvedURL)
            )
        case .plainText:
            guard let text = item.text else { return nil }
            return textPayload(text)
        case .markdown:
            guard let text = item.text else { return nil }
            return textPayload(cleanMarkdown(text, richTextData: item.richTextData))
        case .prettyJSON:
            guard let text = item.text, let formatted = prettyPrintedJSON(text) else { return nil }
            return textPayload(formatted)
        case .markdownLink:
            guard let text = item.text, let link = markdownLink(text) else { return nil }
            return textPayload(link)
        }
    }

    static func prettyPrintedJSON(_ text: String?) -> String? {
        guard let text, let data = text.data(using: .utf8), !text.isEmpty else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }

        guard let prettyData = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
        ) else {
            return nil
        }
        return String(data: prettyData, encoding: .utf8)
    }

    static func markdownLink(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
              let match = detector.firstMatch(in: text, options: [], range: range),
              let url = match.url
        else { return nil }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let host = components?.host ?? url.absoluteString
        let path = components?.path == "/" ? "" : (components?.path ?? "")
        let label = escapeMarkdownLabel(host + path)
        return "[\(label)](\(url.absoluteString))"
    }

    static func cleanMarkdown(_ text: String, richTextData: Data?) -> String {
        if let richTextData,
           let attributedString = try? NSAttributedString(
               data: richTextData,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil
           ) {
            let converted = markdown(from: attributedString)
            if !converted.isEmpty {
                return normalize(converted)
            }
        }
        return normalize(text)
    }

    private static func textPayload(_ text: String) -> ClipboardPastePayload {
        ClipboardPastePayload(
            text: text,
            richTextData: nil,
            imageData: nil,
            imageType: nil,
            fileURLs: []
        )
    }

    private static func markdown(from attributedString: NSAttributedString) -> String {
        var result = ""
        let range = NSRange(location: 0, length: attributedString.length)

        attributedString.enumerateAttributes(in: range, options: []) { attributes, subrange, _ in
            var value = attributedString.attributedSubstring(from: subrange).string

            if let url = attributes[.link] as? URL {
                value = "[\(value)](\(url.absoluteString))"
            }

            if let font = attributes[.font] as? NSFont {
                let traits = font.fontDescriptor.symbolicTraits
                if traits.contains(.bold) { value = "**\(value)**" }
                if traits.contains(.italic) { value = "_\(value)_" }
            }

            result += value
        }
        return result
    }

    private static func normalize(_ text: String) -> String {
        let lineEndingNormalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let trimmedLines = lineEndingNormalized
            .components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: "[ \\t]+$", with: "", options: .regularExpression) }
            .joined(separator: "\n")

        var result = trimmedLines.trimmingCharacters(in: .whitespacesAndNewlines)
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return result
    }

    private static func escapeMarkdownLabel(_ text: String) -> String {
        text.replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }
}
