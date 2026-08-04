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
