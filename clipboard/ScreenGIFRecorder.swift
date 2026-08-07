import AVFoundation
import AppKit
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ScreenGIFRecordingError: LocalizedError {
    case alreadyRecording
    case cancelled
    case noVideoTrack
    case readerFailed(Error?)
    case noFrames
    case couldNotCreateGIF
    case launchFailed(Error)
    case captureFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "A GIF recording is already in progress."
        case .cancelled:
            return "GIF recording cancelled."
        case .noVideoTrack:
            return "The screen recording did not contain a video track."
        case .readerFailed(let error):
            return "The screen recording could not be read: \(error?.localizedDescription ?? "unknown error")"
        case .noFrames:
            return "The screen recording did not contain any frames."
        case .couldNotCreateGIF:
            return "The GIF could not be created."
        case .launchFailed(let error):
            return "Screen recording could not start: \(error.localizedDescription)"
        case .captureFailed(let status):
            return "Screen recording failed (code \(status)). Check Screen Recording permission and try again."
        }
    }
}

enum GIFEncoder {
    private static let framesPerSecond = 10.0
    private static let maximumWidth: CGFloat = 1280

    static func makeGIF(from videoURL: URL) throws -> Data {
        let asset = AVURLAsset(url: videoURL)
        guard let track = asset.tracks(withMediaType: .video).first else {
            throw ScreenGIFRecordingError.noVideoTrack
        }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
        )
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw ScreenGIFRecordingError.readerFailed(nil)
        }
        reader.add(output)
        guard reader.startReading() else {
            throw ScreenGIFRecordingError.readerFailed(reader.error)
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.gif.identifier as CFString,
            0,
            nil
        ) else {
            throw ScreenGIFRecordingError.couldNotCreateGIF
        }

        let properties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0
            ]
        ]
        CGImageDestinationSetProperties(destination, properties as CFDictionary)

        let context = CIContext()
        let frameDelay = 1.0 / framesPerSecond
        var nextFrameTime = 0.0
        var frameCount = 0

        while let sampleBuffer = output.copyNextSampleBuffer() {
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            guard timestamp.isFinite else { continue }
            guard timestamp + 0.0001 >= nextFrameTime else { continue }
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }

            let image = CIImage(cvPixelBuffer: pixelBuffer)
            let renderedImage: CGImage?
            if image.extent.width > maximumWidth {
                let scale = maximumWidth / image.extent.width
                let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                renderedImage = context.createCGImage(scaled, from: scaled.extent)
            } else {
                renderedImage = context.createCGImage(image, from: image.extent)
            }
            guard let renderedImage else { continue }

            let frameProperties: [CFString: Any] = [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: frameDelay
                ]
            ]
            CGImageDestinationAddImage(destination, renderedImage, frameProperties as CFDictionary)
            frameCount += 1
            nextFrameTime = timestamp + frameDelay
        }

        guard reader.status != .failed else {
            throw ScreenGIFRecordingError.readerFailed(reader.error)
        }
        guard frameCount > 0, CGImageDestinationFinalize(destination) else {
            throw ScreenGIFRecordingError.noFrames
        }
        return data as Data
    }

    static func makeGIF(from images: [CGImage], frameDelay: Double = 0.1) throws -> Data {
        guard !images.isEmpty else { throw ScreenGIFRecordingError.noFrames }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.gif.identifier as CFString,
            images.count,
            nil
        ) else {
            throw ScreenGIFRecordingError.couldNotCreateGIF
        }

        let properties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0
            ]
        ]
        CGImageDestinationSetProperties(destination, properties as CFDictionary)

        let safeDelay = max(frameDelay, 0.02)
        for image in images {
            let frameProperties: [CFString: Any] = [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: safeDelay
                ]
            ]
            CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw ScreenGIFRecordingError.couldNotCreateGIF
        }
        return data as Data
    }
}

private final class ScreenRegionSelectionView: NSView {
    var onSelection: ((NSRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: NSPoint?
    private var selectionRect: NSRect?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        selectionRect = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startPoint else { return }
        let currentPoint = convert(event.locationInWindow, from: nil)
        selectionRect = NSRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let startPoint else { return }
        let endPoint = convert(event.locationInWindow, from: nil)
        let rect = NSRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(endPoint.x - startPoint.x),
            height: abs(endPoint.y - startPoint.y)
        )
        guard rect.width >= 8, rect.height >= 8 else {
            self.startPoint = nil
            selectionRect = nil
            needsDisplay = true
            return
        }
        onSelection?(rect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.34).setFill()
        dirtyRect.fill()

        if let selectionRect {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .clear
            selectionRect.fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver

            NSColor.systemBlue.setStroke()
            let border = NSBezierPath(rect: selectionRect)
            border.lineWidth = 2
            border.stroke()
            NSGraphicsContext.restoreGraphicsState()
        } else {
            let message = "Drag to select an area for the GIF  •  Esc to cancel"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 15, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.9)
            ]
            let size = message.size(withAttributes: attributes)
            message.draw(
                at: NSPoint(
                    x: bounds.midX - size.width / 2,
                    y: bounds.maxY - size.height - 32
                ),
                withAttributes: attributes
            )
        }
    }
}

private final class ScreenRegionSelectionWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class ScreenRegionSelector {
    private var windows: [ScreenRegionSelectionWindow] = []
    private var completion: ((CGRect?) -> Void)?
    private var cursorIsPushed = false

    func select(completion: @escaping (CGRect?) -> Void) {
        cancel()
        self.completion = completion
        cursorIsPushed = true
        NSCursor.crosshair.push()

        for screen in NSScreen.screens {
            let window = ScreenRegionSelectionWindow(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

            let view = ScreenRegionSelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.autoresizingMask = [.width, .height]
            view.onSelection = { [weak self, weak window] rect in
                guard let self, let window else { return }
                let appKitRect = window.convertToScreen(rect)
                let captureRect = ScreenGIFRecorder.captureRegion(
                    for: appKitRect,
                    in: screen.frame
                )
                self.finish(captureRect)
            }
            view.onCancel = { [weak self] in self?.finish(nil) }
            window.contentView = view
            windows.append(window)
            window.orderFrontRegardless()
        }

        windows.first?.makeKey()
        windows.first?.makeFirstResponder(windows.first?.contentView)
        NSApp.activate(ignoringOtherApps: true)
    }

    func cancel() {
        guard completion != nil || !windows.isEmpty else { return }
        finish(nil)
    }

    private func finish(_ rect: CGRect?) {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        if cursorIsPushed {
            NSCursor.pop()
            cursorIsPushed = false
        }
        let callback = completion
        completion = nil
        callback?(rect)
    }
}

private final class GIFRecordingCancellationState: @unchecked Sendable {
    private let lock = NSLock()
    private var discarded = false

    func discard() {
        lock.lock()
        discarded = true
        lock.unlock()
    }

    var shouldDiscard: Bool {
        lock.lock()
        defer { lock.unlock() }
        return discarded
    }
}

@MainActor
final class ScreenGIFRecorder {
    private var process: Process?
    private var outputURL: URL?
    private var cancellationState: GIFRecordingCancellationState?
    private let regionSelector = ScreenRegionSelector()
    private var isSelecting = false

    /// Converts AppKit's bottom-left screen coordinates to the top-left
    /// coordinates expected by `screencapture -R`.
    nonisolated static func captureRegion(for appKitRect: CGRect, in screenFrame: CGRect) -> CGRect {
        CGRect(
            x: appKitRect.minX,
            y: screenFrame.maxY - appKitRect.maxY,
            width: appKitRect.width,
            height: appKitRect.height
        )
    }

    static func recordingArguments(region: CGRect, outputPath: String) -> [String] {
        let x = Int(region.origin.x.rounded(.down))
        let y = Int(region.origin.y.rounded(.down))
        let width = max(Int(region.width.rounded(.down)), 1)
        let height = max(Int(region.height.rounded(.down)), 1)
        return ["-R", "\(x),\(y),\(width),\(height)", "-v", "-x", outputPath]
    }

    func start(completion: @escaping (Result<Data, ScreenGIFRecordingError>) -> Void) {
        guard process == nil, !isSelecting else {
            completion(.failure(.alreadyRecording))
            return
        }

        isSelecting = true
        regionSelector.select { [weak self] region in
            guard let self else { return }
            self.isSelecting = false
            guard let region else {
                completion(.failure(.cancelled))
                return
            }
            self.startRecording(region: region, completion: completion)
        }
    }

    private func startRecording(
        region: CGRect,
        completion: @escaping (Result<Data, ScreenGIFRecordingError>) -> Void
    ) {

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipboard-recording-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        let cancellationState = GIFRecordingCancellationState()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // macOS rejects `-i` together with `-v`. Select the region in our own
        // overlay, then use the native fixed-region video recorder.
        process.arguments = Self.recordingArguments(region: region, outputPath: outputURL.path)
        process.terminationHandler = { [weak self] process in
            let shouldDiscard = cancellationState.shouldDiscard
            let result: Result<Data, ScreenGIFRecordingError>

            if shouldDiscard {
                result = .failure(.cancelled)
            } else if FileManager.default.fileExists(atPath: outputURL.path) {
                do {
                    result = .success(try GIFEncoder.makeGIF(from: outputURL))
                } catch let error as ScreenGIFRecordingError {
                    result = .failure(error)
                } catch {
                    result = .failure(.readerFailed(error))
                }
            } else if process.terminationStatus != 0 {
                result = .failure(.captureFailed(process.terminationStatus))
            } else {
                result = .failure(.cancelled)
            }

            try? FileManager.default.removeItem(at: outputURL)
            DispatchQueue.main.async {
                self?.process = nil
                self?.outputURL = nil
                self?.cancellationState = nil
                completion(result)
            }
        }

        do {
            self.outputURL = outputURL
            self.cancellationState = cancellationState
            self.process = process
            try process.run()
        } catch {
            self.process = nil
            self.outputURL = nil
            self.cancellationState = nil
            try? FileManager.default.removeItem(at: outputURL)
            completion(.failure(.launchFailed(error)))
        }
    }

    func cancel() {
        if isSelecting {
            regionSelector.cancel()
            return
        }
        guard let process else { return }
        cancellationState?.discard()
        process.interrupt()
    }

    func finish() {
        if isSelecting {
            regionSelector.cancel()
            return
        }
        process?.interrupt()
    }
}
