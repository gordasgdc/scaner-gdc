// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Foundation

/// Parser + evaluator for the Adobe/Resolve `.cube` format. Declared support (anything else is rejected, never guessed):
///  - exactly one of `LUT_3D_SIZE` (2…129) or `LUT_1D_SIZE` (2…65536); a file with both is rejected (unsupported variant);
///  - `DOMAIN_MIN` / `DOMAIN_MAX` (3 numbers each; max > min per channel); `LUT_3D_INPUT_RANGE`/`LUT_1D_INPUT_RANGE` (2 numbers) are accepted aliases;
///  - `TITLE`, `#` comments, blank lines; data rows of 3 finite numbers, red index varying fastest (3D);
///  - file size ≤ 64 MB. Values outside 0…1 are kept as written (the renderer clamps for display only).
/// Interpolation: trilinear (3D), linear (1D). Input is normalized by the domain and clamped to it.
public struct CubeLUT: Sendable {
    public enum Kind: Sendable, Equatable { case lut1D(Int), lut3D(Int) }
    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case tooLarge(bytes: Int), notText, missingSize, bothSizes, badSize(Int), unsupportedKeyword(String, line: Int)
        case badLine(Int), nonFinite(line: Int), badDomain, wrongRowCount(expected: Int, found: Int), emptyFile
        public var description: String {
            switch self {
            case .tooLarge(let b): "File too large (\(b) bytes; limit 64 MB)"
            case .notText: "Not a text .cube file"
            case .missingSize: "Missing LUT_1D_SIZE / LUT_3D_SIZE"
            case .bothSizes: "Files with both 1D and 3D tables are not supported"
            case .badSize(let s): "Unsupported LUT size \(s)"
            case .unsupportedKeyword(let k, let l): "Unsupported keyword '\(k)' on line \(l)"
            case .badLine(let l): "Malformed line \(l)"
            case .nonFinite(let l): "Non-finite value on line \(l)"
            case .badDomain: "Invalid DOMAIN_MIN/DOMAIN_MAX"
            case .wrongRowCount(let e, let f): "Expected \(e) data rows, found \(f)"
            case .emptyFile: "Empty file"
            }
        }
    }
    public static let maxFileBytes = 64 * 1024 * 1024

    public let kind: Kind
    public let title: String?
    public let domainMin: [Float]
    public let domainMax: [Float]
    /// RGB triples, row-major per the file order.
    public let table: [Float]

    public var size: Int { switch kind { case .lut1D(let n), .lut3D(let n): n } }

    public static func parse(url: URL) throws -> CubeLUT {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let bytes = (attrs[.size] as? Int) ?? 0
        guard bytes <= maxFileBytes else { throw ParseError.tooLarge(bytes: bytes) }
        return try parse(data: try Data(contentsOf: url))
    }

    public static func parse(data: Data) throws -> CubeLUT {
        guard data.count <= maxFileBytes else { throw ParseError.tooLarge(bytes: data.count) }
        guard !data.isEmpty else { throw ParseError.emptyFile }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1), !data.contains(0) else { throw ParseError.notText }
        var title: String?, s1: Int?, s3: Int?
        var dmin: [Float] = [0, 0, 0], dmax: [Float] = [1, 1, 1]
        var table: [Float] = []
        var rows = 0, lineNo = 0
        var expected = 0
        var headerDone = false
        for raw in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            lineNo += 1
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let t = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            let first = String(t[0])
            if let c = first.unicodeScalars.first, CharacterSet.letters.contains(c) {
                guard !headerDone else { throw ParseError.badLine(lineNo) }
                switch first {
                case "TITLE": title = line.dropFirst(5).trimmingCharacters(in: CharacterSet(charactersIn: " \"\t"))
                case "LUT_1D_SIZE": guard t.count == 2, let n = Int(t[1]) else { throw ParseError.badLine(lineNo) }; s1 = n
                case "LUT_3D_SIZE": guard t.count == 2, let n = Int(t[1]) else { throw ParseError.badLine(lineNo) }; s3 = n
                case "DOMAIN_MIN", "DOMAIN_MAX":
                    let v = t.dropFirst().compactMap { Float($0) }
                    guard v.count == 3, t.count == 4, v.allSatisfy(\.isFinite) else { throw ParseError.badDomain }
                    if first == "DOMAIN_MIN" { dmin = v } else { dmax = v }
                case "LUT_3D_INPUT_RANGE", "LUT_1D_INPUT_RANGE":
                    let v = t.dropFirst().compactMap { Float($0) }
                    guard v.count == 2, t.count == 3, v.allSatisfy(\.isFinite) else { throw ParseError.badDomain }
                    dmin = [v[0], v[0], v[0]]; dmax = [v[1], v[1], v[1]]
                default: throw ParseError.unsupportedKeyword(first, line: lineNo)
                }
                continue
            }
            if !headerDone {
                if s1 != nil && s3 != nil { throw ParseError.bothSizes }
                guard s1 != nil || s3 != nil else { throw ParseError.missingSize }
                if let n = s3 { guard (2...129).contains(n) else { throw ParseError.badSize(n) }; expected = n * n * n }
                if let n = s1 { guard (2...65536).contains(n) else { throw ParseError.badSize(n) }; expected = n }
                guard zip(dmin, dmax).allSatisfy({ $0 < $1 }) else { throw ParseError.badDomain }
                table.reserveCapacity(expected * 3)
                headerDone = true
            }
            guard t.count == 3, let r = Float(t[0]), let g = Float(t[1]), let b = Float(t[2]) else { throw ParseError.badLine(lineNo) }
            guard r.isFinite, g.isFinite, b.isFinite else { throw ParseError.nonFinite(line: lineNo) }
            rows += 1
            if rows > expected { throw ParseError.wrongRowCount(expected: expected, found: rows) }
            table.append(r); table.append(g); table.append(b)
        }
        guard s1 != nil || s3 != nil else { throw ParseError.missingSize }
        if s1 != nil && s3 != nil { throw ParseError.bothSizes }
        guard rows == expected else { throw ParseError.wrongRowCount(expected: expected, found: rows) }
        return CubeLUT(kind: s3 != nil ? .lut3D(s3!) : .lut1D(s1!), title: title, domainMin: dmin, domainMax: dmax, table: table)
    }

    /// Evaluates the LUT for one RGB value (in the LUT's input domain). Allocation-free.
    public func apply(_ r: Float, _ g: Float, _ b: Float) -> (Float, Float, Float) {
        @inline(__always) func norm(_ v: Float, _ i: Int) -> Float { min(max((v - domainMin[i]) / (domainMax[i] - domainMin[i]), 0), 1) }
        let nr = norm(r, 0), ng = norm(g, 1), nb = norm(b, 2)
        switch kind {
        case .lut1D(let size):
            @inline(__always) func ch(_ n: Float, _ c: Int) -> Float {
                let p = n * Float(size - 1); let i0 = min(Int(p), size - 1), i1 = min(i0 + 1, size - 1), f = p - Float(i0)
                return table[i0 * 3 + c] * (1 - f) + table[i1 * 3 + c] * f
            }
            return (ch(nr, 0), ch(ng, 1), ch(nb, 2))
        case .lut3D(let size):
            let m = Float(size - 1)
            let pr = nr * m, pg = ng * m, pb = nb * m
            let r0 = min(Int(pr), size - 1), g0 = min(Int(pg), size - 1), b0 = min(Int(pb), size - 1)
            let r1 = min(r0 + 1, size - 1), g1 = min(g0 + 1, size - 1), b1 = min(b0 + 1, size - 1)
            let fr = pr - Float(r0), fg = pg - Float(g0), fb = pb - Float(b0)
            @inline(__always) func at(_ ri: Int, _ gi: Int, _ bi: Int, _ c: Int) -> Float { table[((bi * size + gi) * size + ri) * 3 + c] }
            @inline(__always) func ch(_ c: Int) -> Float {
                let c00 = at(r0, g0, b0, c) * (1 - fr) + at(r1, g0, b0, c) * fr
                let c10 = at(r0, g1, b0, c) * (1 - fr) + at(r1, g1, b0, c) * fr
                let c01 = at(r0, g0, b1, c) * (1 - fr) + at(r1, g0, b1, c) * fr
                let c11 = at(r0, g1, b1, c) * (1 - fr) + at(r1, g1, b1, c) * fr
                return (c00 * (1 - fg) + c10 * fg) * (1 - fb) + (c01 * (1 - fg) + c11 * fg) * fb
            }
            return (ch(0), ch(1), ch(2))
        }
    }
}
