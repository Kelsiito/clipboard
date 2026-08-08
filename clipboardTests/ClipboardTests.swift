import Carbon.HIToolbox
import AppKit
import XCTest
@testable import clipboard

final class ClipboardTests: XCTestCase {
    func testSnapshotFingerprintIsStable() {
        let first = ClipboardSnapshot(text: "hello", richTextData: nil, imageData: nil, imageType: nil, fileURLs: [])
        let second = ClipboardSnapshot(text: "hello", richTextData: nil, imageData: nil, imageType: nil, fileURLs: [])
        XCTAssertEqual(first.fingerprint, second.fingerprint)
    }

    func testDifferentSnapshotsHaveDifferentFingerprints() {
        let first = ClipboardSnapshot(text: "hello", richTextData: nil, imageData: nil, imageType: nil, fileURLs: [])
        let second = ClipboardSnapshot(text: "world", richTextData: nil, imageData: nil, imageType: nil, fileURLs: [])
        XCTAssertNotEqual(first.fingerprint, second.fingerprint)
    }

    @MainActor
    func testStoreDeduplicatesAndPrunes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ClipboardStore(directoryURL: directory, limit: 10)

        for index in 0..<12 {
            store.ingest(ClipboardSnapshot(text: "item-\(index)", richTextData: nil, imageData: nil, imageType: nil, fileURLs: []))
        }
        XCTAssertEqual(store.items.count, 10)
        XCTAssertEqual(store.items.first?.text, "item-11")

        store.ingest(ClipboardSnapshot(text: "item-5", richTextData: nil, imageData: nil, imageType: nil, fileURLs: []))
        XCTAssertEqual(store.items.count, 10)
        XCTAssertEqual(store.items.first?.text, "item-5")

        let reloaded = ClipboardStore(directoryURL: directory, limit: 10)
        XCTAssertEqual(reloaded.items.first?.text, "item-5")
    }

    @MainActor
    func testSnippetStorePersistsUpdatesAndDeletes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = SnippetStore(directoryURL: directory)

        let snippet = try XCTUnwrap(store.add(text: "  curl https://example.com  "))
        XCTAssertEqual(snippet.title, "curl https://example.com")
        XCTAssertEqual(store.snippets.count, 1)

        var updated = snippet
        updated.title = "Health check"
        updated.text = "curl https://example.com/health"
        XCTAssertTrue(store.update(updated))

        let reloaded = SnippetStore(directoryURL: directory)
        XCTAssertEqual(reloaded.snippets.first?.title, "Health check")
        XCTAssertEqual(reloaded.snippets.first?.text, "curl https://example.com/health")
        XCTAssertTrue(reloaded.remove(snippet.id))
        XCTAssertTrue(reloaded.snippets.isEmpty)
    }

    @MainActor
    func testSnippetStoreRejectsEmptyTextAndDeduplicates() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = SnippetStore(directoryURL: directory)

        XCTAssertNil(store.add(text: "   \n"))
        let first = store.add(title: "First", text: "same text")
        let duplicate = store.add(title: "Second", text: "same text")
        XCTAssertEqual(first?.id, duplicate?.id)
        XCTAssertEqual(store.snippets.count, 1)
    }

    @MainActor
    func testStorePinsMaximumThreeItemsAndPersistsOrder() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ClipboardStore(directoryURL: directory)

        for index in 0..<5 {
            store.ingest(ClipboardSnapshot(text: "item-\(index)", richTextData: nil, imageData: nil, imageType: nil, fileURLs: []))
        }

        let candidates = Array(store.items.prefix(4)).map(\.id)
        XCTAssertTrue(store.setPinned(candidates[0], pinned: true))
        XCTAssertTrue(store.setPinned(candidates[1], pinned: true))
        XCTAssertTrue(store.setPinned(candidates[2], pinned: true))
        XCTAssertFalse(store.setPinned(candidates[3], pinned: true))
        XCTAssertEqual(store.items.filter(\.isPinned).count, 3)
        XCTAssertTrue(store.items.prefix(3).allSatisfy(\.isPinned))

        let reloaded = ClipboardStore(directoryURL: directory)
        XCTAssertEqual(reloaded.items.filter(\.isPinned).count, 3)
        XCTAssertTrue(reloaded.items.prefix(3).allSatisfy(\.isPinned))
    }

    func testLegacyItemDecodesWithoutPinnedFlag() throws {
        let item = ClipboardItem(
            fingerprint: "legacy",
            text: "old item",
            richTextData: nil,
            imageData: nil,
            imageType: nil,
            files: []
        )
        let encoded = try JSONEncoder().encode(item)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "isPinned")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(ClipboardItem.self, from: legacyData)
        XCTAssertFalse(decoded.isPinned)
    }

    func testContentLabelsUseEnglishCopy() {
        let textItem = ClipboardItem(
            fingerprint: "text",
            text: "hello",
            richTextData: nil,
            imageData: nil,
            imageType: nil,
            files: []
        )
        let imageItem = ClipboardItem(
            fingerprint: "image",
            text: nil,
            richTextData: nil,
            imageData: Data([1]),
            imageType: "public.png",
            files: []
        )

        XCTAssertEqual(textItem.kindLabel, "Text")
        XCTAssertEqual(imageItem.kindLabel, "Image")
        XCTAssertEqual(imageItem.preview, "Copied image")
    }

    func testClipboardItemSearchMatchesTextCaseAndDiacritics() {
        let item = ClipboardItem(
            fingerprint: "search-text",
            text: "Café receipts for GitHub",
            richTextData: nil,
            imageData: nil,
            imageType: nil,
            files: []
        )

        XCTAssertTrue(item.matchesSearch("cafe"))
        XCTAssertTrue(item.matchesSearch("GITHUB"))
        XCTAssertFalse(item.matchesSearch("invoice"))
        XCTAssertTrue(item.matchesSearch("   "))
    }

    func testClipboardItemSearchMatchesFileMetadata() {
        let fileURL = URL(fileURLWithPath: "/Users/example/Documents/Quarterly Report.pdf")
        let item = ClipboardItem(
            fingerprint: "search-file",
            text: nil,
            richTextData: nil,
            imageData: nil,
            imageType: nil,
            files: [StoredFileReference(url: fileURL, bookmarkData: Data())]
        )

        XCTAssertTrue(item.matchesSearch("quarterly report"))
        XCTAssertTrue(item.matchesSearch("documents"))
        XCTAssertTrue(item.matchesSearch("pdf"))
        XCTAssertFalse(item.matchesSearch("presentation"))
    }

    func testClipboardItemSearchMatchesPersistedOCRText() {
        let item = ClipboardItem(
            fingerprint: "ocr-search",
            text: nil,
            richTextData: nil,
            imageData: Data([1]),
            imageType: "public.png",
            ocrText: "Quarterly revenue forecast",
            files: []
        )

        XCTAssertTrue(item.matchesSearch("quarterly"))
        XCTAssertTrue(item.matchesSearch("REVENUE"))
        XCTAssertFalse(item.matchesSearch("invoice"))
    }

    func testLegacyItemDecodesWithoutOCRText() throws {
        let item = ClipboardItem(
            fingerprint: "legacy-ocr",
            text: nil,
            richTextData: nil,
            imageData: Data([1]),
            imageType: "public.png",
            files: []
        )
        let encoded = try JSONEncoder().encode(item)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "ocrText")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(ClipboardItem.self, from: legacyData)
        XCTAssertNil(decoded.ocrText)
    }

    func testLocalOCRRecognizesSyntheticTextImage() throws {
        let size = NSSize(width: 900, height: 180)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 48, weight: .bold),
            .foregroundColor: NSColor.black
        ]
        NSString(string: "Clipboard OCR").draw(at: NSPoint(x: 30, y: 55), withAttributes: attributes)
        image.unlockFocus()

        let tiffData = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiffData))
        let pngData = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let recognized = try XCTUnwrap(LocalOCRService.recognize(imageData: pngData))

        XCTAssertTrue(recognized.localizedCaseInsensitiveContains("clipboard"))
        XCTAssertTrue(recognized.localizedCaseInsensitiveContains("ocr"))
    }

    @MainActor
    func testStoreRemovesSingleItemAndPersistsDeletion() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ClipboardStore(directoryURL: directory)
        store.ingest(ClipboardSnapshot(text: "keep", richTextData: nil, imageData: nil, imageType: nil, fileURLs: []))
        store.ingest(ClipboardSnapshot(text: "remove", richTextData: nil, imageData: nil, imageType: nil, fileURLs: []))

        let itemToRemove = try! XCTUnwrap(store.items.first(where: { $0.text == "remove" }))
        XCTAssertTrue(store.remove(itemToRemove.id))
        XCTAssertFalse(store.items.contains(where: { $0.id == itemToRemove.id }))

        let reloaded = ClipboardStore(directoryURL: directory)
        XCTAssertEqual(reloaded.items.map(\.text), ["keep"])
    }

    @MainActor
    func testStoreClearsOnlyUnpinnedItems() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ClipboardStore(directoryURL: directory)
        store.ingest(ClipboardSnapshot(text: "unpinned", richTextData: nil, imageData: nil, imageType: nil, fileURLs: []))
        store.ingest(ClipboardSnapshot(text: "pinned", richTextData: nil, imageData: nil, imageType: nil, fileURLs: []))
        let pinnedID = try! XCTUnwrap(store.items.first(where: { $0.text == "pinned" })).id
        XCTAssertTrue(store.setPinned(pinnedID, pinned: true))

        XCTAssertEqual(store.clearUnpinned(), 1)
        XCTAssertEqual(store.items.map(\.text), ["pinned"])

        let reloaded = ClipboardStore(directoryURL: directory)
        XCTAssertEqual(reloaded.items.map(\.text), ["pinned"])
        XCTAssertTrue(reloaded.items[0].isPinned)
    }

    @MainActor
    func testStoreRetentionRemovesOldUnpinnedItemsButKeepsPinnedItems() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ClipboardStore(directoryURL: directory, retention: .oneDay)
        let oldDate = Date(timeIntervalSince1970: 1_000)

        store.ingest(
            ClipboardSnapshot(text: "old unpinned", richTextData: nil, imageData: nil, imageType: nil, fileURLs: []),
            now: oldDate
        )
        store.ingest(
            ClipboardSnapshot(text: "old pinned", richTextData: nil, imageData: nil, imageType: nil, fileURLs: []),
            now: oldDate
        )
        let pinnedID = try! XCTUnwrap(store.items.first(where: { $0.text == "old pinned" })).id
        XCTAssertTrue(store.setPinned(pinnedID, pinned: true))

        let removed = store.pruneExpired(now: oldDate.addingTimeInterval(2 * 24 * 60 * 60))
        XCTAssertEqual(removed, 1)
        XCTAssertEqual(store.items.map(\.text), ["old pinned"])
        XCTAssertTrue(store.items[0].isPinned)
    }

    func testRetentionOptionsHaveExpectedTitlesAndIntervals() {
        XCTAssertEqual(ClipboardRetention.allCases, [.never, .oneDay, .sevenDays, .thirtyDays])
        XCTAssertNil(ClipboardRetention.never.interval)
        XCTAssertEqual(ClipboardRetention.oneDay.interval, 24 * 60 * 60)
        XCTAssertEqual(ClipboardRetention.sevenDays.title, "7 days")
        XCTAssertEqual(ClipboardRetention.thirtyDays.title, "30 days")
    }

    @MainActor
    func testIgnoreNextCopyIsConsumedOnce() {
        let monitor = PasteboardMonitor()
        XCTAssertFalse(monitor.isIgnoringNextCopy)
        monitor.ignoreNextCopy()
        XCTAssertTrue(monitor.isIgnoringNextCopy)
        XCTAssertTrue(monitor.consumeIgnoreNextCopy())
        XCTAssertFalse(monitor.isIgnoringNextCopy)
        XCTAssertFalse(monitor.consumeIgnoreNextCopy())
    }

    @MainActor
    func testPasteboardMonitorPauseCanBeResumed() {
        let monitor = PasteboardMonitor()
        XCTAssertFalse(monitor.isPaused)

        monitor.pauseHistory(for: .untilResumed)
        XCTAssertTrue(monitor.isPaused)

        monitor.resumeHistory()
        XCTAssertFalse(monitor.isPaused)
    }

    @MainActor
    func testPasteboardMonitorFiltersIgnoredApplications() {
        let monitor = PasteboardMonitor()
        monitor.ignoredBundleIdentifiers = ["com.example.private"]

        XCTAssertTrue(monitor.shouldIgnore(bundleIdentifier: "com.example.private"))
        XCTAssertFalse(monitor.shouldIgnore(bundleIdentifier: "com.example.editor"))
        XCTAssertFalse(monitor.shouldIgnore(bundleIdentifier: nil))
    }

    func testClipboardStackPreservesCopyOrderAndConsumesItems() {
        let first = UUID()
        let second = UUID()
        var stack = ClipboardStack()

        stack.append(first)
        stack.append(second)

        XCTAssertEqual(stack.count, 2)
        XCTAssertEqual(stack.removeFirst(), first)
        XCTAssertEqual(stack.removeFirst(), second)
        XCTAssertNil(stack.removeFirst())
        XCTAssertTrue(stack.isEmpty)
    }

    func testAppearanceModesMapToExpectedColorSchemes() {
        XCTAssertNil(ClipboardAppearance.system.colorScheme)
        XCTAssertEqual(ClipboardAppearance.light.colorScheme, .light)
        XCTAssertEqual(ClipboardAppearance.dark.colorScheme, .dark)
        XCTAssertEqual(ClipboardAppearance.allCases, [.system, .light, .dark])
    }

    func testMaterialOptionsIncludeLiquidGlassAndStandard() {
        XCTAssertEqual(ClipboardMaterial.allCases, [.liquidGlass, .standard])
        XCTAssertEqual(ClipboardMaterial.liquidGlass.title, "Liquid Glass")
        XCTAssertEqual(ClipboardMaterial.standard.title, "Standard")
    }

    func testSmartPastePlainTextDropsRichContent() throws {
        let item = ClipboardItem(
            fingerprint: "rich-text",
            text: "hello",
            richTextData: Data([1, 2, 3]),
            imageData: nil,
            imageType: nil,
            files: []
        )

        let payload = try XCTUnwrap(ClipboardPasteFormatter.payload(for: item, format: .plainText))
        XCTAssertEqual(payload.text, "hello")
        XCTAssertNil(payload.richTextData)
        XCTAssertNil(payload.imageData)
        XCTAssertTrue(payload.fileURLs.isEmpty)
    }

    func testSmartPasteFormatsJSONAndSortsKeys() throws {
        let input = #"{"z":1,"a":[true,false]}"#
        let formatted = try XCTUnwrap(ClipboardPasteFormatter.prettyPrintedJSON(input))

        XCTAssertEqual(formatted, "{\n  \"a\" : [\n    true,\n    false\n  ],\n  \"z\" : 1\n}")
    }

    func testSmartPasteRejectsInvalidJSON() {
        XCTAssertNil(ClipboardPasteFormatter.prettyPrintedJSON("not json"))
    }

    func testSmartPasteCreatesMarkdownLinkWithoutNetworkAccess() throws {
        let markdown = try XCTUnwrap(ClipboardPasteFormatter.markdownLink("https://example.com/docs/start"))
        XCTAssertEqual(markdown, "[example.com/docs/start](https://example.com/docs/start)")
    }

    func testSmartPasteAvailabilityOnlyShowsApplicableFormats() {
        let item = ClipboardItem(
            fingerprint: "json",
            text: "{\"name\":\"clipboard\"}",
            richTextData: nil,
            imageData: nil,
            imageType: nil,
            files: []
        )

        XCTAssertEqual(
            ClipboardPasteFormat.available(for: item),
            [.original, .plainText, .markdown, .prettyJSON]
        )
    }

    @MainActor
    func testStoreClearRemovesHistoryOnly() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ClipboardStore(directoryURL: directory)
        store.ingest(ClipboardSnapshot(text: "keep", richTextData: nil, imageData: nil, imageType: nil, fileURLs: []))
        store.clear()
        XCTAssertTrue(store.items.isEmpty)
    }

    @MainActor
    func testImagePayloadPersists() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ClipboardStore(directoryURL: directory)
        let imageData = Data([0, 1, 2, 3])
        store.ingest(ClipboardSnapshot(text: nil, richTextData: nil, imageData: imageData, imageType: "public.png", fileURLs: []))

        let reloaded = ClipboardStore(directoryURL: directory)
        XCTAssertEqual(reloaded.items.first?.imageData, imageData)
        XCTAssertEqual(reloaded.items.first?.imageType, "public.png")
    }

    @MainActor
    func testGIFPayloadPersistsAndKeepsGIFPasteType() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ClipboardStore(directoryURL: directory)
        let gifData = Data("GIF89a".utf8)

        store.ingest(ClipboardSnapshot(
            text: nil,
            richTextData: nil,
            imageData: gifData,
            imageType: "com.compuserve.gif",
            fileURLs: []
        ))

        let item = try XCTUnwrap(store.items.first)
        XCTAssertTrue(item.isGIF)
        XCTAssertEqual(item.kindLabel, "GIF")
        XCTAssertEqual(item.preview, "Copied GIF")

        let payload = try XCTUnwrap(ClipboardPasteFormatter.payload(for: item, format: .original))
        XCTAssertEqual(payload.imageData, gifData)
        XCTAssertEqual(payload.imageType, "com.compuserve.gif")
    }

    func testGIFFileExporterWritesDataAndAddsExtension() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let chosenURL = directory.appendingPathComponent("recording")
        let data = Data([1, 2, 3])

        let outputURL = try GIFFileExporter.write(data, to: chosenURL)

        XCTAssertEqual(outputURL.pathExtension, "gif")
        XCTAssertEqual(try Data(contentsOf: outputURL), data)
    }

    @MainActor
    func testFileBookmarkPersistsAndResolves() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = directory.appendingPathComponent("source.txt")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("file".utf8).write(to: source)

        let store = ClipboardStore(directoryURL: directory.appendingPathComponent("history"))
        store.ingest(ClipboardSnapshot(text: nil, richTextData: nil, imageData: nil, imageType: nil, fileURLs: [source]))

        XCTAssertEqual(store.items.first?.files.count, 1)
        XCTAssertEqual(store.items.first?.files.first?.resolvedURL?.standardizedFileURL.path, source.standardizedFileURL.path)
    }

    @MainActor
    func testEmptySnapshotIsIgnored() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ClipboardStore(directoryURL: directory)
        store.ingest(ClipboardSnapshot(text: nil, richTextData: nil, imageData: nil, imageType: nil, fileURLs: []))
        XCTAssertTrue(store.items.isEmpty)
    }

    func testDefaultHotKeyIsCommandShiftV() {
        XCTAssertEqual(HotKeyConfiguration.default.keyCode, 9)
        XCTAssertTrue(HotKeyConfiguration.default.displayString.contains("⌘"))
        XCTAssertTrue(HotKeyConfiguration.default.displayString.contains("⇧"))
        XCTAssertTrue(HotKeyConfiguration.default.displayString.contains("V"))
    }

    func testDefaultGIFHotKeyIsCommandG() {
        XCTAssertEqual(HotKeyConfiguration.gifDefault.keyCode, 5)
        XCTAssertEqual(HotKeyConfiguration.gifDefault.modifiers, UInt32(cmdKey))
        XCTAssertEqual(HotKeyConfiguration.gifDefault.displayString, "⌘G")
    }

    func testAnnotationToolsKeepTheMVPSet() {
        XCTAssertEqual(AnnotationTool.allCases, [.draw, .line, .arrow, .rectangle])
    }

    @MainActor
    func testAnnotationDocumentRendersPNG() throws {
        let image = NSImage(size: NSSize(width: 120, height: 80))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 120, height: 80).fill()
        image.unlockFocus()

        let document = AnnotationDocument(image: image)
        document.selectedTool = .rectangle
        document.begin(at: CGPoint(x: 10, y: 10), in: CGSize(width: 120, height: 80))
        document.update(to: CGPoint(x: 90, y: 60), in: CGSize(width: 120, height: 80))
        document.finish()

        let data = try XCTUnwrap(document.renderedPNGData())
        XCTAssertFalse(data.isEmpty)
        XCTAssertEqual(document.marks.count, 1)
    }

    func testGIFEncoderCreatesGIFData() throws {
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        NSColor.systemRed.setFill()
        NSRect(x: 0, y: 0, width: 16, height: 16).fill()
        image.unlockFocus()

        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let data = try GIFEncoder.makeGIF(from: [cgImage, cgImage])

        XCTAssertTrue(data.starts(with: Data("GIF".utf8)))
        XCTAssertGreaterThan(data.count, 20)
    }

    @MainActor
    func testGIFRecorderUsesSelectionOverlayAndFixedRegionVideoCapture() {
        let arguments = ScreenGIFRecorder.recordingArguments(
            region: CGRect(x: 10, y: 20, width: 300, height: 200),
            outputPath: "/tmp/clipboard-test.mov"
        )

        XCTAssertEqual(arguments, ["-R", "10,20,300,200", "-v", "-x", "/tmp/clipboard-test.mov"])
        XCTAssertFalse(arguments.contains("-i"))
        XCTAssertFalse(arguments.contains("-U"))
    }

    func testGIFRecorderConvertsAppKitRegionToScreenCaptureCoordinates() {
        let appKitRegion = CGRect(x: 120, y: 700, width: 240, height: 120)
        let screenFrame = CGRect(x: 0, y: 0, width: 1470, height: 956)

        let captureRegion = ScreenGIFRecorder.captureRegion(
            for: appKitRegion,
            in: screenFrame
        )

        XCTAssertEqual(captureRegion, CGRect(x: 120, y: 136, width: 240, height: 120))
    }

    func testPanelPlacementUsesCaretAnchor() {
        let origin = ClipboardPanelPlacement.origin(
            anchor: NSRect(x: 700, y: 180, width: 1, height: 22),
            panelSize: NSSize(width: 460, height: 300),
            visibleFrame: NSRect(x: 0, y: 0, width: 1512, height: 950)
        )

        XCTAssertEqual(origin.x, 470.5, accuracy: 0.001)
        XCTAssertEqual(origin.y, 214, accuracy: 0.001)
    }

    func testComposerAnchorUsesBottomOfWindowInsteadOfMousePosition() {
        let anchor = ClipboardPanelPlacement.composerAnchor(
            in: CGRect(x: 0, y: 33, width: 1470, height: 923)
        )

        XCTAssertEqual(anchor.midX, 735, accuracy: 0.001)
        XCTAssertEqual(anchor.minY, 860, accuracy: 0.001)
        XCTAssertEqual(anchor.width, 1, accuracy: 0.001)
        XCTAssertEqual(anchor.height, 1, accuracy: 0.001)
    }

    func testPanelPlacementFlipsBelowCaretNearTopEdge() {
        let origin = ClipboardPanelPlacement.origin(
            anchor: NSRect(x: 700, y: 920, width: 1, height: 22),
            panelSize: NSSize(width: 460, height: 300),
            visibleFrame: NSRect(x: 0, y: 0, width: 1512, height: 950)
        )

        XCTAssertEqual(origin.x, 470.5, accuracy: 0.001)
        XCTAssertEqual(origin.y, 608, accuracy: 0.001)
    }

    func testPanelPlacementClampsToVisibleScreen() {
        let origin = ClipboardPanelPlacement.origin(
            anchor: NSRect(x: 5, y: 5, width: 1, height: 22),
            panelSize: NSSize(width: 460, height: 300),
            visibleFrame: NSRect(x: 0, y: 0, width: 1512, height: 950)
        )

        XCTAssertEqual(origin.x, 12, accuracy: 0.001)
        XCTAssertEqual(origin.y, 39, accuracy: 0.001)
    }
}
