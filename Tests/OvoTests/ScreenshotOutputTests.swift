import AppKit
import Testing
@testable import Ovo

@MainActor
struct ScreenshotOutputTests {
    private func withOutput(_ test: (URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Ovo-Screenshot-Test-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try test(folder.appendingPathComponent("selection.png"))
    }

    private func imageData(tiff: Bool = false) throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 10, pixelsHigh: 10,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        return try #require(bitmap.representation(using: tiff ? .tiff : .png, properties: [:]))
    }

    @Test(arguments: [false, true])
    func controlRedirectedCaptureRecoversPNGAndTIFF(tiff: Bool) throws {
        try withOutput { url in
            let clipboard = FakeScreenshotClipboard(data: try imageData(tiff: tiff), changeCount: 2)
            try ScreenshotCaptureOutput.resolve(status: 0, imageURL: url, diagnostic: "",
                initialClipboardChangeCount: 1, clipboard: clipboard)
            let recovered = try Data(contentsOf: url)
            #expect(Array(recovered.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10])
            #expect(NSBitmapImageRep(data: recovered)?.pixelsWide == 10)
            #expect(clipboard.changeCount == 2)
        }
    }

    @Test
    func normalFileCaptureNeverReadsClipboard() throws {
        try withOutput { url in
            let original = try imageData()
            try original.write(to: url)
            let clipboard = FakeScreenshotClipboard(data: nil, changeCount: 2)
            try ScreenshotCaptureOutput.resolve(status: 0, imageURL: url, diagnostic: "",
                initialClipboardChangeCount: 1, clipboard: clipboard)
            #expect(clipboard.readCount == 0)
            #expect(try Data(contentsOf: url) == original)
        }
    }

    @Test(arguments: [Int32(0), Int32(1)])
    func escapeDoesNotTranslateAnOldClipboardImage(status: Int32) throws {
        try withOutput { url in
            let clipboard = FakeScreenshotClipboard(data: try imageData(), changeCount: 1)
            #expect(throws: PlatformError.cancelled) {
                try ScreenshotCaptureOutput.resolve(status: status, imageURL: url, diagnostic: "",
                    initialClipboardChangeCount: 1, clipboard: clipboard)
            }
            #expect(clipboard.readCount == 0)
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test
    func clipboardChangedDuringReadIsNotUsed() throws {
        try withOutput { url in
            let clipboard = FakeScreenshotClipboard(data: try imageData(), changeCount: 2)
            clipboard.changeDuringRead = true
            #expect(throws: PlatformError.cancelled) {
                try ScreenshotCaptureOutput.resolve(status: 0, imageURL: url, diagnostic: "",
                    initialClipboardChangeCount: 1, clipboard: clipboard)
            }
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test
    func screenshotErrorIsNotSilentlyTreatedAsEscape() throws {
        try withOutput { url in
            let clipboard = FakeScreenshotClipboard(data: nil, changeCount: 1)
            #expect(throws: PlatformError.screenshotFailed("could not create image")) {
                try ScreenshotCaptureOutput.resolve(status: 1, imageURL: url,
                    diagnostic: "could not create image\n", initialClipboardChangeCount: 1, clipboard: clipboard)
            }
        }
    }
}

@MainActor
private final class FakeScreenshotClipboard: ScreenshotClipboard {
    var changeCount: Int
    let data: Data?
    var readCount = 0
    var changeDuringRead = false
    init(data: Data?, changeCount: Int) { self.data = data; self.changeCount = changeCount }
    func imageData() -> Data? {
        readCount += 1
        if changeDuringRead { changeCount += 1 }
        return data
    }
}
