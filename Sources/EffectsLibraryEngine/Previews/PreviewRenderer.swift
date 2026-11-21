// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Foundation
import CoreGraphics
import ImageIO
import CryptoKit

public enum LUTPreviewRenderer {
    /// Bump when rendering math/encoding changes (part of the cache key).
    public static let version = 1

    /// Applies the LUT to the reference and encodes an 8-bit sRGB-tagged image. Deterministic.
    public static func render(_ lut: CubeLUT, reference: ReferenceImage) -> CGImage? {
        var out = [UInt8](repeating: 255, count: reference.width * reference.height * 4)
        reference.pixels.withUnsafeBufferPointer { src in
            for i in 0..<(reference.width * reference.height) {
                let (r, g, b) = lut.apply(src[i * 3], src[i * 3 + 1], src[i * 3 + 2])
                out[i * 4] = quantize(r); out[i * 4 + 1] = quantize(g); out[i * 4 + 2] = quantize(b)
            }
        }
        return image(rgba: &out, width: reference.width, height: reference.height)
    }

    public static func renderOriginal(_ reference: ReferenceImage) -> CGImage? {
        var out = [UInt8](repeating: 255, count: reference.width * reference.height * 4)
        for i in 0..<(reference.width * reference.height) {
            out[i * 4] = quantize(reference.pixels[i * 3]); out[i * 4 + 1] = quantize(reference.pixels[i * 3 + 1]); out[i * 4 + 2] = quantize(reference.pixels[i * 3 + 2])
        }
        return image(rgba: &out, width: reference.width, height: reference.height)
    }

    @inline(__always) static func quantize(_ v: Float) -> UInt8 { UInt8(min(max(v, 0), 1) * 255 + 0.5) }

    static func image(rgba: inout [UInt8], width: Int, height: Int) -> CGImage? {
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return rgba.withUnsafeMutableBytes { raw in
            CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: cs,
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?.makeImage()
        }
    }

    public static func png(_ image: CGImage) -> Data? {
        let d = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(d, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? d as Data : nil
    }
}

public enum BundleIconLoader {
    /// Decodes the bundle's `.icns` (data file) with ImageIO at a bounded size. No plugin code is loaded.
    public static func iconPNG(at icns: URL, maxPixel: Int = 128) -> Data? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: icns.path), (attrs[.size] as? Int ?? 0) <= 8 * 1024 * 1024,
              let src = CGImageSourceCreateWithURL(icns as CFURL, nil), CGImageSourceGetCount(src) > 0 else { return nil }
        // choose the largest representation, then downscale
        var best = 0, bestW = 0
        for i in 0..<CGImageSourceGetCount(src) {
            if let p = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any], let w = p[kCGImagePropertyPixelWidth] as? Int, w > bestW { best = i; bestW = w }
        }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                                     kCGImageSourceCreateThumbnailWithTransform: true]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, best, opts as CFDictionary) else { return nil }
        return LUTPreviewRenderer.png(img)
    }
}

public enum ContentHasher {
    /// Streaming SHA-256 (1 MB chunks); nil when the file cannot be read.
    public static func sha256(of url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try? h.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
