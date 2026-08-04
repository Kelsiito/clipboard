import Foundation

@MainActor
final class ClipboardStore: ObservableObject {
    static let maximumPinnedItems = 3

    @Published private(set) var items: [ClipboardItem] = []

    private let fileManager = FileManager.default
    private let historyURL: URL
    private(set) var limit: Int

    init(directoryURL: URL? = nil, limit: Int = 50) {
        let directory = directoryURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("clipboard", isDirectory: true)
        historyURL = directory.appendingPathComponent("history.json")
        self.limit = min(max(limit, 10), 200)
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

    func ingest(_ snapshot: ClipboardSnapshot) {
        guard !snapshot.isEmpty else { return }
        let fileReferences = snapshot.fileURLs.compactMap(makeFileReference)
        let wasPinned = items.first(where: { $0.fingerprint == snapshot.fingerprint })?.isPinned ?? false
        let item = ClipboardItem(
            fingerprint: snapshot.fingerprint,
            text: snapshot.text,
            richTextData: snapshot.richTextData,
            imageData: snapshot.imageData,
            imageType: snapshot.imageType,
            files: fileReferences,
            isPinned: wasPinned
        )
        guard !item.isEmpty else { return }

        items.removeAll { $0.fingerprint == item.fingerprint }
        items.insert(item, at: 0)
        sortItems()
        items = Array(items.prefix(limit))
        save()
    }

    func clear() {
        items.removeAll()
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
            let data = try Data(contentsOf: historyURL)
            items = Array(try JSONDecoder.clipboardDecoder.decode([ClipboardItem].self, from: data).prefix(limit))
            normalizePinnedItems()
            sortItems()
        } catch {
            items = []
        }
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
        do {
            let directory = historyURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder.clipboardEncoder.encode(items)
            try data.write(to: historyURL, options: .atomic)
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: historyURL.path)
        } catch {
            // Clipboard capture stays functional in memory if disk persistence fails.
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
