// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Foundation
import CryptoKit

/// The synthetic reference image used to preview LUTs.
/// Provenance/rights: generated procedurally by this code (original work of GDC, no third-party image, no license encumbrance).
/// Color assumption: RGB code values in 0…1 are fed to the LUT as its input; the result is tagged sRGB for display only.
/// A LUT built for another input space (e.g. a log encoding) therefore shows the effect on these code values, not a
/// colorimetrically correct rendering. Changing the generator requires bumping `version` (it is part of the cache key).
public struct ReferenceImage: Sendable {
    public static let version = "gdc-ref-1"
    public let width: Int
    public let height: Int
    /// RGB float triples, row-major, top row first.
    public let pixels: [Float]

    public static func make(width: Int = 384, height: Int = 240) -> ReferenceImage {
        var px = [Float](repeating: 0, count: width * height * 3)
        func set(_ x: Int, _ y: Int, _ c: (Float, Float, Float)) { let i = (y * width + x) * 3; px[i] = c.0; px[i + 1] = c.1; px[i + 2] = c.2 }
        func hsv(_ h: Float, _ s: Float, _ v: Float) -> (Float, Float, Float) {
            let c = v * s, hh = (h * 6).truncatingRemainder(dividingBy: 6), x = c * (1 - abs(hh.truncatingRemainder(dividingBy: 2) - 1)), m = v - c
            let t: (Float, Float, Float) = switch Int(hh) { case 0: (c, x, 0); case 1: (x, c, 0); case 2: (0, c, x); case 3: (0, x, c); case 4: (x, 0, c); default: (c, 0, x) }
            return (t.0 + m, t.1 + m, t.2 + m)
        }
        let band = height / 4
        let patches: [(Float, Float, Float)] = [(1,0,0),(0,1,0),(0,0,1),(0,1,1),(1,0,1),(1,1,0),(0.5,0,0),(0,0.5,0),(0,0,0.5),(0,0.5,0.5),(0.5,0,0.5),(0.5,0.5,0)]
        let skin: [(Float, Float, Float)] = [(0.96,0.80,0.69),(0.87,0.69,0.55),(0.76,0.57,0.45),(0.62,0.44,0.34),(0.47,0.32,0.24),(0.33,0.22,0.17)]
        for y in 0..<height {
            for x in 0..<width {
                let u = Float(x) / Float(width - 1)
                switch y / max(band, 1) {
                case 0: set(x, y, (u, u, u))                                                    // gray ramp
                case 1: let p = patches[min(x * patches.count / width, patches.count - 1)]; set(x, y, p)   // saturated patches
                case 2: set(x, y, hsv(u * 0.999, 0.8, 0.8))                                      // hue sweep
                default:
                    if x < width / 2 { set(x, y, skin[min(x * skin.count / (width / 2), skin.count - 1)]) }   // skin-like tones
                    else { let v = Float(x - width / 2) / Float(width / 2 - 1); set(x, y, (0.15 + 0.7 * v, 0.2 + 0.5 * v, 0.3 + 0.4 * v)) } // soft ramp
                }
            }
        }
        return ReferenceImage(width: width, height: height, pixels: px)
    }

    /// Hash of the pixel data: part of the preview cache key, so a changed generator invalidates old previews.
    public var contentHash: String {
        pixels.withUnsafeBufferPointer { SHA256.hash(data: Data(buffer: $0)).map { String(format: "%02x", $0) }.joined() }
    }
    public var id: String { "\(Self.version)-\(width)x\(height)" }
}
