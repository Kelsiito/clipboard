import Foundation

@MainActor
final class ClipboardStore: ObservableObject {
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
            items = Array(items.prefix(limit))
            save()
        }
    }

    func ingest(_ snapshot: ClipboardSnapshot) {
        guard !snapshot.isEmpty else { return }
        let fileReferences = snapshot.fileURLs.compactMap(makeFileReference)
        let item = ClipboardItem(
            fingerprint: snapshot.fingerprint,
            text: snapshot.text,
            richTextData: snapshot.richTextData,
            imageData: snapshot.imageData,
            imageType: snapshot.imageType,
            files: fileReferences
        )
        guard !item.isEmpty else { return }

        items.removeAll { $0.fingerprint == item.fingerprint }
        items.insert(item, at: 0)
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
        } catch {
            items = []
        }
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
