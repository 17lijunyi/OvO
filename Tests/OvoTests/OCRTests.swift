import AppKit
import Testing
@testable import Ovo

@MainActor
struct OCRTests {
    @Test
    func recognizesEnglishAndChineseFromLocalImage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Ovo-OCR-Test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("fixture.png")
        let context = try #require(CGContext(data: nil, width: 1000, height: 240, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1000, height: 240))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 46), .foregroundColor: NSColor.black]
        ("Hello world" as NSString).draw(at: NSPoint(x: 30, y: 140), withAttributes: attributes)
        ("你好，世界" as NSString).draw(at: NSPoint(x: 30, y: 50), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        let image = try #require(context.makeImage())
        let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try png.write(to: url)
        let result = try ScreenshotOCRService.recognizeText(in: url)
        #expect(result.contains("Hello world"))
        #expect(result.contains("你好"))
        #expect(result.contains("世界"))
    }
}
