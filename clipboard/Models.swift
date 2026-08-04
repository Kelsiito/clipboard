import AppKit
import Carbon.HIToolbox
import CryptoKit
import Foundation

enum ClipboardContentKind: String, Codable {
    case text
    case image
    case files
    case mixed
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

    var hasText: Bool { text?.isEmpty == false }
    var hasImage: Bool { imageData != nil }
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
        case .text: return "Texto"
        case .image: return "Imagem"
        case .files: return files.count == 1 ? "Ficheiro" : "Ficheiros"
        case .mixed: return "Conteúdo misto"
        }
    }

    var preview: String {
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if hasFiles { return files.map(\.name).joined(separator: ", ") }
        if hasImage { return "Imagem copiada" }
        return "Conteúdo copiado"
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        fingerprint: String,
        text: String?,
        richTextData: Data?,
        imageData: Data?,
        imageType: String?,
        files: [StoredFileReference]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.fingerprint = fingerprint
        self.text = text
        self.richTextData = richTextData
        self.imageData = imageData
        self.imageType = imageType
        self.files = files
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
