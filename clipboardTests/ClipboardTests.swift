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
}
