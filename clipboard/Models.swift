import AppKit
import Carbon.HIToolbox
import CryptoKit
import Foundation
import UniformTypeIdentifiers

enum ClipboardContentKind: String, Codable {
    case text
    case image
    case files
    case mixed
}

enum ClipboardRetention: String, CaseIterable, Codable, Hashable, Identifiable {
    case never
    case oneDay
    case sevenDays
    case thirtyDays

    var id: String { rawValue }

    var title: String {
        switch self {
        case .never: return "Never"
        case .oneDay: return "1 day"
        case .sevenDays: return "7 days"
        case .thirtyDays: return "30 days"
        }
    }

    var interval: TimeInterval? {
        switch self {
        case .never: return nil
        case .oneDay: return 24 * 60 * 60
        case .sevenDays: return 7 * 24 * 60 * 60
        case .thirtyDays: return 30 * 24 * 60 * 60
        }
    }
}

enum ClipboardPauseDuration: String, CaseIterable, Hashable, Identifiable {
    case fifteenMinutes
    case oneHour
    case untilResumed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fifteenMinutes: return "15 minutes"
        case .oneHour: return "1 hour"
        case .untilResumed: return "Until resumed"
        }
    }

    var interval: TimeInterval? {
        switch self {
        case .fifteenMinutes: return 15 * 60
        case .oneHour: return 60 * 60
        case .untilResumed: return nil
        }
    }
}

struct ClipboardStack: Equatable {
    private(set) var itemIDs: [UUID] = []

    var count: Int { itemIDs.count }
    var isEmpty: Bool { itemIDs.isEmpty }

    mutating func append(_ id: UUID) {
        itemIDs.append(id)
    }

    @discardableResult
    mutating func removeFirst() -> UUID? {
        guard !itemIDs.isEmpty else { return nil }
        return itemIDs.removeFirst()
    }

    mutating func removeAll() {
        itemIDs.removeAll()
    }
}

struct StoredFileReference: Codable, Hashable, Identifiable {
    let id: UUID
    let name: String
    let path: String
    let bookmarkData: Data

    init(url: URL, bookmarkData: Data) {
        id = UUID()
        name = url.lastPathComponent
        path = url.path
        self.bookmarkData = bookmarkData
    }

    var resolvedURL: URL? {
        var isStale = false
        if let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            return url
        }
        return URL(fileURLWithPath: path)
    }
}

struct ClipboardItem: Codable, Equatable, Identifiable {
    let id: UUID
    var createdAt: Date
    var fingerprint: String
    var text: String?
    var richTextData: Data?
    var imageData: Data?
    var imageType: String?
    var files: [StoredFileReference]
    var isPinned: Bool

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, fingerprint, text, richTextData, imageData, imageType, files, isPinned
    }

    var hasText: Bool { text?.isEmpty == false }
    var hasImage: Bool { imageData != nil }
    var isGIF: Bool { imageType == UTType.gif.identifier }
    var hasFiles: Bool { !files.isEmpty }
    var isEmpty: Bool { !hasText && !hasImage && !hasFiles }

    var kind: ClipboardContentKind {
        let count = [hasText, hasImage, hasFiles].filter { $0 }.count
        if count > 1 { return .mixed }
        if hasImage { return .image }
        if hasFiles { return .files }
        return .text
    }

    var kindLabel: String {
        switch kind {
        case .text: return "Text"
        case .image: return isGIF ? "GIF" : "Image"
        case .files: return files.count == 1 ? "File" : "Files"
        case .mixed: return "Mixed content"
        }
    }

    var preview: String {
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if hasFiles { return files.map(\.name).joined(separator: ", ") }
        if hasImage { return isGIF ? "Copied GIF" : "Copied image" }
        return "Copied content"
    }

    /// Search-only projection. It is intentionally not persisted so filtering
    /// cannot change the stored history format or data.
    var searchableText: String {
        var values = [text ?? "", preview, kindLabel]
        values.append(contentsOf: files.flatMap { [$0.name, $0.path] })
        return values.joined(separator: "\n")
    }

    func matchesSearch(_ query: String) -> Bool {
        let normalizedQuery = query.searchNormalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return true }
        return searchableText.searchNormalized.localizedStandardContains(normalizedQuery)
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        fingerprint: String,
        text: String?,
        richTextData: Data?,
        imageData: Data?,
        imageType: String?,
        files: [StoredFileReference],
        isPinned: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.fingerprint = fingerprint
        self.text = text
        self.richTextData = richTextData
        self.imageData = imageData
        self.imageType = imageType
        self.files = files
        self.isPinned = isPinned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        fingerprint = try container.decode(String.self, forKey: .fingerprint)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        richTextData = try container.decodeIfPresent(Data.self, forKey: .richTextData)
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        imageType = try container.decodeIfPresent(String.self, forKey: .imageType)
        files = try container.decode([StoredFileReference].self, forKey: .files)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(fingerprint, forKey: .fingerprint)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(richTextData, forKey: .richTextData)
        try container.encodeIfPresent(imageData, forKey: .imageData)
        try container.encodeIfPresent(imageType, forKey: .imageType)
        try container.encode(files, forKey: .files)
        try container.encode(isPinned, forKey: .isPinned)
    }
}

private extension String {
    var searchNormalized: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

struct ClipboardSnapshot {
    let text: String?
    let richTextData: Data?
    let imageData: Data?
    let imageType: String?
    let fileURLs: [URL]

    var isEmpty: Bool {
        let hasText = text?.isEmpty == false
        return !hasText && imageData == nil && fileURLs.isEmpty
    }

    var fingerprint: String {
        var data = Data()
        if let text { data.append(Data(text.utf8)) }
        if let richTextData { data.append(richTextData) }
        if let imageData { data.append(imageData) }
        if let imageType { data.append(Data(imageType.utf8)) }
        for url in fileURLs { data.append(Data(url.standardizedFileURL.path.utf8)) }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

struct HotKeyConfiguration: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let `default` = HotKeyConfiguration(keyCode: 9, modifiers: UInt32(cmdKey | shiftKey))
    static let gifDefault = HotKeyConfiguration(keyCode: 5, modifiers: UInt32(cmdKey))

    var displayString: String {
        var value = ""
        if modifiers & UInt32(controlKey) != 0 { value += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { value += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { value += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { value += "⌘" }
        return value + keyName
    }

    private var keyName: String {
        let names: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y",
            17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K",
            45: "N", 46: "M", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
            25: "9", 26: "7", 28: "8", 29: "0", 36: "↩", 48: "⇥", 49: "Space", 51: "⌫",
            53: "Esc", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down"
        ]
        return names[keyCode] ?? "Key (keyCode)"
    }

    static func modifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }
}
