import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private struct IconBuildError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private func makeIconset(sourceURL: URL, outputURL: URL) throws {
    guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
        throw IconBuildError(message: "Cannot read source icon: \(sourceURL.path)")
    }
    guard image.width == image.height, image.width > 0 else {
        throw IconBuildError(message: "Source icon must be square; received \(image.width) × \(image.height).")
    }
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
        throw IconBuildError(message: "Cannot create the icon color space.")
    }
    try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

    // Standard macOS iconset: 16, 32, 128, 256 and 512 points, each at 1× and 2×.
    // Every size comes directly from the original artwork, never from another thumbnail.
    for size in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let pixels = size * scale
            guard let context = CGContext(
                data: nil,
                width: pixels,
                height: pixels,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                throw IconBuildError(message: "Cannot create \(pixels) × \(pixels) icon bitmap.")
            }
            let bounds = CGRect(x: 0, y: 0, width: pixels, height: pixels)
            context.clear(bounds)
            context.interpolationQuality = .high
            context.setShouldAntialias(true)
            context.setBlendMode(.copy)
            context.draw(image, in: bounds)

            let suffix = scale == 2 ? "@2x" : ""
            let target = outputURL.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
            guard let resized = context.makeImage(),
                  let destination = CGImageDestinationCreateWithURL(target as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                throw IconBuildError(message: "Cannot write icon: \(target.path)")
            }
            CGImageDestinationAddImage(destination, resized, nil)
            guard CGImageDestinationFinalize(destination) else {
                throw IconBuildError(message: "Failed to finish icon: \(target.path)")
            }
        }
    }
}

do {
    guard CommandLine.arguments.count == 3 else {
        throw IconBuildError(message: "Usage: swift make-icon.swift <source.png> <output.iconset>")
    }
    try makeIconset(
        sourceURL: URL(fileURLWithPath: CommandLine.arguments[1]),
        outputURL: URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    )
} catch {
    FileHandle.standardError.write(Data("make-icon: \(error.localizedDescription)\n".utf8))
    exit(1)
}
