import AppKit
import CoreGraphics
import ImageIO
import Vision

@MainActor
final class ScreenshotOCRService {
    private var isCapturing = false

    static var hasScreenRecordingPermission: Bool { CGPreflightScreenCaptureAccess() }

    @discardableResult
    static func requestScreenRecordingPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func captureAndRecognize() async throws -> String {
        try Task.checkCancellation()
        guard !isCapturing else { throw PlatformError.cancelled }
        guard Self.hasScreenRecordingPermission else {
            throw PlatformError.screenRecordingPermissionRequired
        }
        isCapturing = true
        defer { isCapturing = false }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Ovo-Capture-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: temporaryDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw PlatformError.screenshotFailed(error.localizedDescription)
        }
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let imageURL = temporaryDirectory.appendingPathComponent("selection.png")
        let clipboard = ScreenshotPasteboard()
        let initialClipboardChangeCount = clipboard.changeCount
        let errorURL = temporaryDirectory.appendingPathComponent("capture-error.txt")
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        let errorFile = try FileHandle(forWritingTo: errorURL)
        defer { try? errorFile.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-s", "-x", "-t", "png", imageURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorFile

        do {
            try Task.checkCancellation()
            let status = try await CancellableCaptureProcess(process: process).run()
            try Task.checkCancellation()
            let diagnostic = (try? String(contentsOf: errorURL, encoding: .utf8)) ?? ""
            try ScreenshotCaptureOutput.resolve(
                status: status, imageURL: imageURL, diagnostic: diagnostic,
                initialClipboardChangeCount: initialClipboardChangeCount, clipboard: clipboard
            )
        } catch is CancellationError {
            throw PlatformError.cancelled
        } catch let error as PlatformError {
            throw error
        } catch {
            throw PlatformError.screenshotFailed(error.localizedDescription)
        }

        do {
            let text = try await Task.detached(priority: .userInitiated) {
                try Self.recognizeText(in: imageURL)
            }.value
            try Task.checkCancellation()
            return text
        } catch is CancellationError {
            throw PlatformError.cancelled
        } catch let error as PlatformError {
            throw error
        } catch {
            throw PlatformError.recognitionFailed(error.localizedDescription)
        }
    }

    /// Only recognized text leaves this layer; screenshot pixels stay on the Mac.
    nonisolated static func recognizeText(in imageURL: URL) throws -> String {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw PlatformError.screenshotFailed("无法读取截图文件。")
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw PlatformError.noRecognizedText }
        return text
    }
}

@MainActor
protocol ScreenshotClipboard {
    var changeCount: Int { get }
    func imageData() -> Data?
}

@MainActor
private final class ScreenshotPasteboard: ScreenshotClipboard {
    var changeCount: Int { NSPasteboard.general.changeCount }
    func imageData() -> Data? {
        NSPasteboard.general.data(forType: .png) ?? NSPasteboard.general.data(forType: .tiff)
    }
}

/// Holding Control during the system picker redirects its output to the clipboard,
/// even when a filename was supplied. Accept only a new, stable image from this run;
/// never OCR an old clipboard image after Escape or modify the user's clipboard.
@MainActor
enum ScreenshotCaptureOutput {
    static func resolve(status: Int32, imageURL: URL, diagnostic: String,
                        initialClipboardChangeCount: Int, clipboard: any ScreenshotClipboard) throws {
        let hasFile = FileManager.default.fileExists(atPath: imageURL.path)
        if status == 0, hasFile { return }
        if status == 0, !hasFile {
            let observedCount = clipboard.changeCount
            if observedCount != initialClipboardChangeCount,
               let data = clipboard.imageData(), clipboard.changeCount == observedCount,
               let bitmap = NSBitmapImageRep(data: data),
               let png = bitmap.representation(using: .png, properties: [:]) {
                try png.write(to: imageURL, options: .atomic)
                return
            }
        }
        let detail = diagnostic.trimmingCharacters(in: .whitespacesAndNewlines)
        if !detail.isEmpty { throw PlatformError.screenshotFailed(String(detail.prefix(500))) }
        if !hasFile, status == 0 || status == 1 { throw PlatformError.cancelled }
        throw PlatformError.screenshotFailed("系统截图进程退出，状态码 \(status)。")
    }
}

/// Serializes process startup with cancellation so an early cancel cannot launch
/// an orphaned system screenshot picker after the caller has moved on.
final class CancellableCaptureProcess: @unchecked Sendable {
    private let process: Process
    private let lock = NSLock()
    private var cancelled = false
    private var started = false

    init(process: Process) { self.process = process }

    func run() async throws -> Int32 {
        let status: Int32 = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                guard !cancelled, !started else {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                started = true
                process.terminationHandler = { process in
                    continuation.resume(returning: process.terminationStatus)
                }
                do {
                    try process.run()
                    lock.unlock()
                } catch {
                    process.terminationHandler = nil
                    lock.unlock()
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            self.lock.lock()
            self.cancelled = true
            if self.process.isRunning { self.process.terminate() }
            self.lock.unlock()
        }
        try Task.checkCancellation()
        return status
    }
}
