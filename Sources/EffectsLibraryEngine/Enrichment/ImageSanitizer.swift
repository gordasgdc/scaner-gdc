// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Foundation
import ImageIO
import UniformTypeIdentifiers
import CryptoKit

/// Turns untrusted image bytes into a safe local PNG: real type sniffed from the bytes (never from the URL or header),
/// dimensions read before decoding, bounded size and pixels, downscaled (aspect ratio kept), re-encoded (metadata dropped).
/// SVG, HTML and anything that is not PNG/JPEG/GIF/WebP is refused.
public enum ImageSanitizer {
    public struct Limits: Sendable {
        public var maxBytes = 8 * 1024 * 1024
        public var maxSide = 8192
        public var maxPixels = 40_000_000
        public var outputMaxSide = 960
        public init() {}
    }
    public struct Clean: Sendable { public let png: Data; public let width: Int; public let height: Int; public var fileName: String { Self.name(png) }
        static func name(_ d: Data) -> String { SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined() + ".png" } }
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case empty, tooLarge, unsupportedType, undecodable, dimensionsTooLarge, animatedOrMultiFrame
        public var description: String {
            switch self {
            case .empty: "The image is empty."
            case .tooLarge: "The image file is too large."
            case .unsupportedType: "Unsupported image type (PNG, JPEG, GIF and WebP only)."
            case .undecodable: "The image could not be decoded."
            case .dimensionsTooLarge: "The image dimensions are too large."
            case .animatedOrMultiFrame: "Animated images are not accepted."
            }
        }
    }

    public static func sniff(_ d: Data) -> UTType? {
        let b = [UInt8](d.prefix(16))
        if b.count >= 8, Array(b[0..<8]) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] { return .png }
        if b.count >= 3, b[0] == 0xFF, b[1] == 0xD8, b[2] == 0xFF { return .jpeg }
        if b.count >= 6, Array(b[0..<4]) == [0x47, 0x49, 0x46, 0x38] { return .gif }
        if b.count >= 12, Array(b[0..<4]) == [0x52, 0x49, 0x46, 0x46], Array(b[8..<12]) == [0x57, 0x45, 0x42, 0x50] { return .webP }
        return nil
    }

    public static func sanitize(_ data: Data, limits: Limits = Limits()) -> Result<Clean, Failure> {
        if data.isEmpty { return .failure(.empty) }
        if data.count > limits.maxBytes { return .failure(.tooLarge) }
        guard sniff(data) != nil else { return .failure(.unsupportedType) }
        let opts: CFDictionary = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data as CFData, opts) else { return .failure(.undecodable) }
        guard CGImageSourceGetCount(src) == 1 else { return .failure(CGImageSourceGetCount(src) > 1 ? .animatedOrMultiFrame : .undecodable) }
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int, w > 0, h > 0 else { return .failure(.undecodable) }
        if w > limits.maxSide || h > limits.maxSide || w * h > limits.maxPixels { return .failure(.dimensionsTooLarge) }
        let thumbOpts: CFDictionary = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                       kCGImageSourceThumbnailMaxPixelSize: limits.outputMaxSide, kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts) else { return .failure(.undecodable) }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return .failure(.undecodable) }
        CGImageDestinationAddImage(dest, img, nil)   // no source properties: EXIF/ICC text/XMP are not carried over
        guard CGImageDestinationFinalize(dest) else { return .failure(.undecodable) }
        return .success(Clean(png: out as Data, width: img.width, height: img.height))
    }
}
