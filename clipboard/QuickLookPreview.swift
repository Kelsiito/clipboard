import AppKit
import QuickLookUI
import UniformTypeIdentifiers

final class ClipboardQuickLookPreview: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private final class PreviewItem: NSObject, QLPreviewItem {
        let url: URL
        let title: String

        init(url: URL, title: String) {
            self.url = url
            self.title = title
        }

        var previewItemURL: URL? { url }
        var previewItemTitle: String? { title }
    }

    private var items: [PreviewItem] = []
    private var temporaryURLs: [URL] = []

    @discardableResult
    func show(item: ClipboardItem) -> Bool {
        guard let panel = QLPreviewPanel.shared() else { return false }
        if panel.isVisible {
            panel.orderOut(nil)
            cleanupTemporaryFiles()
        }

        let previewItems = makePreviewItems(for: item)
        guard !previewItems.isEmpty else { return false }

        items = previewItems
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        return true
    }

    func close() {
        QLPreviewPanel.shared()?.orderOut(nil)
        cleanupTemporaryFiles()
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel) -> Int {
        items.count
    }

    func previewPanel(_ panel: QLPreviewPanel, previewItemAt index: Int) -> QLPreviewItem {
        items[index]
    }

    func windowWillClose(_ notification: Notification) {
        cleanupTemporaryFiles()
    }

    deinit {
        cleanupTemporaryFiles()
    }

    private func makePreviewItems(for item: ClipboardItem) -> [PreviewItem] {
        var result: [PreviewItem] = []

        if let imageData = item.imageData,
           let imageURL = makeTemporaryImageURL(data: imageData, imageType: item.imageType) {
            result.append(PreviewItem(url: imageURL, title: item.isGIF ? "Copied GIF" : "Copied image"))
        }

        for file in item.files {
            guard let url = file.resolvedURL,
                  FileManager.default.fileExists(atPath: url.path)
            else { continue }
            result.append(PreviewItem(url: url, title: file.name))
        }

        if result.isEmpty,
           let text = item.text,
           let textURL = makeTemporaryTextURL(text: text) {
            result.append(PreviewItem(url: textURL, title: "Copied text"))
        }

        return result
    }

    private func makeTemporaryImageURL(data: Data, imageType: String?) -> URL? {
        let type = imageType.flatMap(UTType.init) ?? .png
        let fileExtension = type.preferredFilenameExtension ?? "png"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipboard-preview-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)
        do {
            try data.write(to: url, options: .atomic)
            temporaryURLs.append(url)
            return url
        } catch {
            return nil
        }
    }

    private func makeTemporaryTextURL(text: String) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipboard-preview-\(UUID().uuidString)")
            .appendingPathExtension("txt")
        do {
            try text.data(using: .utf8)?.write(to: url, options: .atomic)
            temporaryURLs.append(url)
            return url
        } catch {
            return nil
        }
    }

    private func cleanupTemporaryFiles() {
        for url in temporaryURLs {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryURLs.removeAll()
        items.removeAll()
    }
}
