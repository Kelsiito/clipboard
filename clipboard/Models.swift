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

struct ClipboardSourceApplication: Codable, Equatable, Hashable, Identifiable {
    let bundleIdentifier: String
    let name: String

    var id: String { bundleIdentifier }

    init(bundleIdentifier: String, name: String) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
    }

    var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty { return trimmedName }
        return bundleIdentifier
    }
}

enum ClipboardHistoryTypeFilter: String, CaseIterable, Hashable, Identifiable {
    case all
    case text
    case image
    case gif
    case files
    case mixed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All types"
        case .text: return "Text"
        case .image: return "Images"
        case .gif: return "GIFs"
        case .files: return "Files"
        case .mixed: return "Mixed"
        }
    }

    func matches(_ item: ClipboardItem) -> Bool {
        switch self {
        case .all: return true
        case .text: return item.kind == .text
        case .image: return item.kind == .image && !item.isGIF
        case .gif: return item.isGIF
        case .files: return item.kind == .files
        case .mixed: return item.kind == .mixed
        }
    }
}

enum ClipboardHistoryDateFilter: String, CaseIterable, Hashable, Identifiable {
    case allTime
    case today
    case lastSevenDays
    case lastThirtyDays

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allTime: return "All time"
        case .today: return "Today"
        case .lastSevenDays: return "Last 7 days"
        case .lastThirtyDays: return "Last 30 days"
        }
    }

    func includes(_ date: Date, now: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .allTime:
            return true
        case .today:
            return date >= calendar.startOfDay(for: now)
        case .lastSevenDays:
            return date >= now.addingTimeInterval(-7 * 24 * 60 * 60)
        case .lastThirtyDays:
            return date >= now.addingTimeInterval(-30 * 24 * 60 * 60)
        }
    }
}

struct ClipboardHistoryFilter: Equatable {
    var type: ClipboardHistoryTypeFilter = .all
    var date: ClipboardHistoryDateFilter = .allTime
    var sourceAppBundleIdentifier: String?
    var pinnedOnly = false
    var hasOCR = false

    var activeFilterCount: Int {
        (type == .all ? 0 : 1)
            + (date == .allTime ? 0 : 1)
            + (sourceAppBundleIdentifier == nil ? 0 : 1)
            + (pinnedOnly ? 1 : 0)
            + (hasOCR ? 1 : 0)
    }

    var isDefault: Bool { activeFilterCount == 0 }
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
    var ocrText: String?
    var files: [StoredFileReference]
    var isPinned: Bool
    var sourceApplication: ClipboardSourceApplication?

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, fingerprint, text, richTextData, imageData, imageType, ocrText, files, isPinned, sourceApplication
    }

    var hasText: Bool { text?.isEmpty == false }
    var hasImage: Bool { imageData != nil }
    var isGIF: Bool { imageType == UTType.gif.identifier }
    var canExtractText: Bool { hasImage && !isGIF }
    var hasFiles: Bool { !files.isEmpty }
    var isEmpty: Bool { !hasText && !hasImage && !hasFiles }
    var sourceApplicationLabel: String? { sourceApplication?.displayName }

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
        var values = [text ?? "", ocrText ?? "", preview, kindLabel]
        values.append(contentsOf: files.flatMap { [$0.name, $0.path] })
        return values.joined(separator: "\n")
    }

    func matchesSearch(_ query: String) -> Bool {
        let normalizedQuery = query.searchNormalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return true }
        return searchableText.searchNormalized.localizedStandardContains(normalizedQuery)
    }

    func matches(_ filter: ClipboardHistoryFilter, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard filter.type.matches(self),
              filter.date.includes(createdAt, now: now, calendar: calendar),
              filter.sourceAppBundleIdentifier == nil || sourceApplication?.bundleIdentifier == filter.sourceAppBundleIdentifier,
              !filter.pinnedOnly || isPinned,
              !filter.hasOCR || ocrText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else { return false }
        return true
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        fingerprint: String,
        text: String?,
        richTextData: Data?,
        imageData: Data?,
        imageType: String?,
        ocrText: String? = nil,
        files: [StoredFileReference],
        isPinned: Bool = false,
        sourceApplication: ClipboardSourceApplication? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.fingerprint = fingerprint
        self.text = text
        self.richTextData = richTextData
        self.imageData = imageData
        self.imageType = imageType
        self.ocrText = ocrText
        self.files = files
        self.isPinned = isPinned
        self.sourceApplication = sourceApplication
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
        ocrText = try container.decodeIfPresent(String.self, forKey: .ocrText)
        files = try container.decode([StoredFileReference].self, forKey: .files)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        sourceApplication = try container.decodeIfPresent(ClipboardSourceApplication.self, forKey: .sourceApplication)
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
        try container.encodeIfPresent(ocrText, forKey: .ocrText)
        try container.encode(files, forKey: .files)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encodeIfPresent(sourceApplication, forKey: .sourceApplication)
    }
}

struct ClipboardSnippet: Codable, Equatable, Identifiable {
    let id: UUID
    var createdAt: Date
    var title: String
    var text: String
    var collection: String?
    var tags: [String]

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        title: String,
        text: String,
        collection: String? = nil,
        tags: [String] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.text = text
        self.collection = Self.normalizedCollection(collection)
        self.tags = Self.normalizedTags(tags)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case title
        case text
        case collection
        case tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        title = try container.decode(String.self, forKey: .title)
        text = try container.decode(String.self, forKey: .text)
        collection = Self.normalizedCollection(try container.decodeIfPresent(String.self, forKey: .collection))
        tags = Self.normalizedTags(try container.decodeIfPresent([String].self, forKey: .tags) ?? [])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(title, forKey: .title)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(collection, forKey: .collection)
        try container.encode(tags, forKey: .tags)
    }

    static func suggestedTitle(for text: String) -> String {
        let firstLine = text
            .split(maxSplits: 1, whereSeparator: { $0.isNewline })
            .first
            .map(String.init) ?? "Favorite"
        let trimmed = firstLine.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Favorite" }
        return String(trimmed.prefix(48))
    }

    static func normalizedCollection(_ collection: String?) -> String? {
        guard let collection else { return nil }
        let trimmed = collection.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(64))
    }

    static func normalizedTags(_ tags: [String]) -> [String] {
        var normalized: [String] = []
        var seen = Set<String>()

        for tag in tags {
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let value = String(trimmed.prefix(32))
            let key = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seen.insert(key).inserted else { continue }
            normalized.append(value)
        }

        return Array(normalized.prefix(12))
    }

    func matchesLibrary(
        query: String,
        collection selectedCollection: String?,
        tag selectedTag: String?
    ) -> Bool {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchesQuery = trimmedQuery.isEmpty
            || title.localizedStandardContains(trimmedQuery)
            || text.localizedStandardContains(trimmedQuery)
            || (collection?.localizedStandardContains(trimmedQuery) == true)
            || tags.contains(where: { $0.localizedStandardContains(trimmedQuery) })
        let matchesCollection = selectedCollection.map { collection == $0 } ?? true
        let matchesTag = selectedTag.map { tags.contains($0) } ?? true
        return matchesQuery && matchesCollection && matchesTag
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
