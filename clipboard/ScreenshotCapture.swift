import AppKit
import Foundation

enum ScreenshotCaptureError: LocalizedError {
    case alreadyCapturing
    case cancelled
    case invalidImage
    case launchFailed(Error)

    var errorDescription: String? {
        switch self {
        case .alreadyCapturing:
            return "A screen capture is already in progress."
        case .cancelled:
            return "Screen capture cancelled."
        case .invalidImage:
            return "The captured image could not be opened."
        case .launchFailed(let error):
            return "Screen capture could not start: \(error.localizedDescription)"
        }
    }
}

@MainActor
final class ScreenshotCaptureService {
    private var process: Process?

    func captureSelection(completion: @escaping (Result<NSImage, ScreenshotCaptureError>) -> Void) {
        guard process == nil else {
            completion(.failure(.alreadyCapturing))
            return
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipboard-capture-\(UUID().uuidString)")
            .appendingPathExtension("png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", outputURL.path]
        process.terminationHandler = { [weak self] process in
            let result: Result<NSImage, ScreenshotCaptureError>
            if process.terminationStatus != 0 {
                result = .failure(.cancelled)
            } else if let data = try? Data(contentsOf: outputURL),
                      let image = NSImage(data: data) {
                // Decode before deleting the temporary file. NSImage(contentsOf:)
                // can keep a lazy file-backed representation, which renders blank
                // after the capture file is removed.
                result = .success(image)
            } else {
                result = .failure(.invalidImage)
            }
            try? FileManager.default.removeItem(at: outputURL)

            DispatchQueue.main.async {
                self?.process = nil
                completion(result)
            }
        }

        do {
            self.process = process
            try process.run()
        } catch {
            self.process = nil
            try? FileManager.default.removeItem(at: outputURL)
            completion(.failure(.launchFailed(error)))
        }
    }
}
