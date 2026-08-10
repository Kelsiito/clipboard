import Foundation
import UniformTypeIdentifiers

@MainActor
final class ClipboardStore: ObservableObject {
    static let maximumPinnedItems = 3

    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var persistenceErrorMessage: String?

    private let fileManager = FileManager.default
    private let historyURL: URL
    private let cipher: LocalDataCipher
    private var canPersist = true
    private(set) var limit: Int
    private(set) var retention: ClipboardRetention

    init(
        directoryURL: URL? = nil,
        limit: Int = 50,
        retention: ClipboardRetention = .never,
        cipher: LocalDataCipher = .keychainBacked
    ) {
        let directory = directoryURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("clipboard", isDirectory: true)
        historyURL = directory.appendingPathComponent("history.json")
        self.cipher = cipher
        self.limit = min(max(limit, 10), 200)
        self.retention = retention
        load()
    }

    func setLimit(_ value: Int) {
        limit = min(max(value, 10), 200)
        if items.count > limit {
            sortItems()
            items = Array(items.prefix(limit))
            save()
        }
    }

    func setRetention(_ value: ClipboardRetention, now: Date = Date()) {
        retention = value
        if pruneExpired(now: now, persist: false) > 0 {
            save()
        }
    }

    @discardableResult
    func setPinned(_ id: UUID, pinned: Bool) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        if pinned && !items[index].isPinned {
            guard items.filter(\.isPinned).count < Self.maximumPinnedItems else { return false }
        }

        items[index].isPinned = pinned
        sortItems()
        save()
        return true
    }

    @discardableResult
    func remove(_ id: UUID) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        items.remove(at: index)
        save()
        return true
    }

    func item(withID id: UUID) -> ClipboardItem? {
        items.first(where: { $0.id == id })
    }

    @discardableResult
    func clearUnpinned() -> Int {
        let originalCount = items.count
        items.removeAll { !$0.isPinned }
        let removedCount = originalCount - items.count
        if removedCount > 0 { save() }
        return removedCount
    }

    func ingest(
        _ snapshot: ClipboardSnapshot,
        sourceApplication: ClipboardSourceApplication? = nil,
        now: Date = Date()
    ) {
        guard !snapshot.isEmpty else { return }
        let fileReferences = snapshot.fileURLs.compactMap(makeFileReference)
        let existingItem = items.first(where: { $0.fingerprint == snapshot.fingerprint })
        let wasPinned = existingItem?.isPinned ?? false
        let item = ClipboardItem(
            createdAt: now,
            fingerprint: snapshot.fingerprint,
            text: snapshot.text,
            richTextData: snapshot.richTextData,
            imageData: snapshot.imageData,
            imageType: snapshot.imageType,
            files: fileReferences,
            isPinned: wasPinned,
            sourceApplication: sourceApplication ?? existingItem?.sourceApplication
        )
        guard !item.isEmpty else { return }

        items.removeAll { $0.fingerprint == item.fingerprint }
        items.insert(item, at: 0)
        _ = pruneExpired(now: now, persist: false)
        sortItems()
        items = Array(items.prefix(limit))
        save()
        scheduleOCRIfNeeded(for: item)
    }

    @discardableResult
    func pruneExpired(now: Date = Date()) -> Int {
        pruneExpired(now: now, persist: true)
    }

    func clear() {
        items.removeAll()
        save()
    }

    private func setOCRText(_ text: String, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard items[index].ocrText != text else { return }
        items[index].ocrText = text
        save()
    }

    private func makeFileReference(url: URL) -> StoredFileReference? {
        let bookmark: Data
        do {
            bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            guard let fallback = try? url.bookmarkData() else { return nil }
            bookmark = fallback
        }
        return StoredFileReference(url: url, bookmarkData: bookmark)
    }

    private func load() {
        guard fileManager.fileExists(atPath: historyURL.path) else { return }
        do {
            let storedData = try Data(contentsOf: historyURL)
            let openedData = try cipher.open(storedData, purpose: "clipboard-history")
            items = Array(try JSONDecoder.clipboardDecoder.decode([ClipboardItem].self, from: openedData.plaintext).prefix(limit))
            normalizePinnedItems()
            let removedCount = pruneExpired(now: Date(), persist: false)
            sortItems()
            if removedCount > 0 || !openedData.wasEncrypted { save() }
            items.forEach { scheduleOCRIfNeeded(for: $0) }
        } catch {
            items = []
            canPersist = false
            persistenceErrorMessage = "Encrypted history could not be opened. Existing data was preserved."
        }
    }

    private func scheduleOCRIfNeeded(for item: ClipboardItem) {
        guard item.ocrText == nil,
              let imageData = item.imageData,
              item.imageType != UTType.gif.identifier else { return }

        let itemID = item.id
        Task { [weak self] in
            let recognizedText = await Task.detached(priority: .utility) {
                LocalOCRService.recognize(imageData: imageData)
            }.value

            guard let recognizedText, !recognizedText.isEmpty else { return }
            self?.setOCRText(recognizedText, for: itemID)
        }
    }

    private func pruneExpired(now: Date, persist: Bool) -> Int {
        guard let interval = retention.interval else { return 0 }
        let cutoff = now.addingTimeInterval(-interval)
        let originalCount = items.count
        items.removeAll { !$0.isPinned && $0.createdAt < cutoff }
        let removedCount = originalCount - items.count
        if removedCount > 0 && persist { save() }
        return removedCount
    }

    private func normalizePinnedItems() {
        var pinnedCount = 0
        for index in items.indices where items[index].isPinned {
            if pinnedCount < Self.maximumPinnedItems {
                pinnedCount += 1
            } else {
                items[index].isPinned = false
            }
        }
    }

    private func sortItems() {
        let pinned = items.filter(\.isPinned)
        let unpinned = items.filter { !$0.isPinned }
        items = pinned + unpinned
    }

    private func save() {
        guard canPersist else { return }
        do {
            let directory = historyURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let plaintext = try JSONEncoder.clipboardEncoder.encode(items)
            let encryptedData = try cipher.seal(plaintext, purpose: "clipboard-history")
            try encryptedData.write(to: historyURL, options: .atomic)
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: historyURL.path)
        } catch {
            canPersist = false
            persistenceErrorMessage = "Encrypted history could not be saved. Clipboard capture remains available in memory."
        }
    }
}

@MainActor
final class SnippetStore: ObservableObject {
    @Published private(set) var snippets: [ClipboardSnippet] = []
    @Published private(set) var persistenceErrorMessage: String?

    private let fileManager = FileManager.default
    private let snippetsURL: URL
    private let cipher: LocalDataCipher
    private var canPersist = true

    init(directoryURL: URL? = nil, cipher: LocalDataCipher = .keychainBacked) {
        let directory = directoryURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("clipboard", isDirectory: true)
        snippetsURL = directory.appendingPathComponent("snippets.json")
        self.cipher = cipher
        load()
    }

    @discardableResult
    func add(
        title: String? = nil,
        text: String,
        collection: String? = nil,
        tags: [String] = [],
        now: Date = Date()
    ) -> ClipboardSnippet? {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else { return nil }
        if let existing = snippets.first(where: { $0.text == normalizedText }) {
            return existing
        }

        let normalizedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let snippet = ClipboardSnippet(
            createdAt: now,
            title: normalizedTitle?.isEmpty == false
                ? normalizedTitle!
                : ClipboardSnippet.suggestedTitle(for: normalizedText),
            text: normalizedText,
            collection: collection,
            tags: tags
        )
        snippets.insert(snippet, at: 0)
        save()
        return snippet
    }

    @discardableResult
    func update(_ snippet: ClipboardSnippet) -> Bool {
        let normalizedText = snippet.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty,
              let index = snippets.firstIndex(where: { $0.id == snippet.id })
        else { return false }

        var updated = snippet
        updated.title = snippet.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if updated.title.isEmpty {
            updated.title = ClipboardSnippet.suggestedTitle(for: normalizedText)
        }
        updated.text = normalizedText
        updated.collection = ClipboardSnippet.normalizedCollection(snippet.collection)
        updated.tags = ClipboardSnippet.normalizedTags(snippet.tags)
        snippets[index] = updated
        sortSnippets()
        save()
        return true
    }

    @discardableResult
    func upsert(_ snippet: ClipboardSnippet) -> Bool {
        if snippets.contains(where: { $0.id == snippet.id }) {
            return update(snippet)
        }
        return add(
            title: snippet.title,
            text: snippet.text,
            collection: snippet.collection,
            tags: snippet.tags,
            now: snippet.createdAt
        ) != nil
    }

    @discardableResult
    func remove(_ id: UUID) -> Bool {
        guard let index = snippets.firstIndex(where: { $0.id == id }) else { return false }
        snippets.remove(at: index)
        save()
        return true
    }

    private func load() {
        guard fileManager.fileExists(atPath: snippetsURL.path) else { return }
        do {
            let storedData = try Data(contentsOf: snippetsURL)
            let openedData = try cipher.open(storedData, purpose: "clipboard-library")
            snippets = try JSONDecoder.clipboardDecoder.decode([ClipboardSnippet].self, from: openedData.plaintext)
            snippets = snippets.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            sortSnippets()
            if !openedData.wasEncrypted { save() }
        } catch {
            snippets = []
            canPersist = false
            persistenceErrorMessage = "Encrypted Library data could not be opened. Existing data was preserved."
        }
    }

    private func sortSnippets() {
        snippets.sort { $0.createdAt > $1.createdAt }
    }

    private func save() {
        guard canPersist else { return }
        do {
            let directory = snippetsURL.deletingLastPathComponent()
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let plaintext = try JSONEncoder.clipboardEncoder.encode(snippets)
            let encryptedData = try cipher.seal(plaintext, purpose: "clipboard-library")
            try encryptedData.write(to: snippetsURL, options: .atomic)
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: snippetsURL.path)
        } catch {
            canPersist = false
            persistenceErrorMessage = "Encrypted Library data could not be saved. Items remain available in memory."
        }
    }
}

private extension JSONEncoder {
    static var clipboardEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var clipboardDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
