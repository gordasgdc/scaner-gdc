// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Foundation

/// Mach-O architecture names read from the first bytes of an executable. Never loads or runs it.
public enum MachOReader {
    public static func architectures(at url: URL) -> [String]? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        guard let d = try? h.read(upToCount: 4096), d.count >= 8 else { return nil }
        return architectures(in: d)
    }

    public static func architectures(in d: Data) -> [String]? {
        func u32(_ o: Int, big: Bool) -> UInt32? {
            guard o + 4 <= d.count else { return nil }
            let b = d[d.startIndex + o ..< d.startIndex + o + 4].map(UInt32.init)
            return big ? (b[0] << 24 | b[1] << 16 | b[2] << 8 | b[3]) : (b[3] << 24 | b[2] << 16 | b[1] << 8 | b[0])
        }
        func name(_ cpu: UInt32, _ sub: UInt32) -> String {
            switch cpu {
            case 0x0100000C: return (sub & 0xFFFFFF) == 2 ? "arm64e" : "arm64"
            case 0x01000007: return "x86_64"
            case 7: return "i386"
            case 12: return "arm"
            case 0x0200000C: return "arm64_32"
            default: return "cpu\(cpu)"
            }
        }
        guard let magic = u32(0, big: true) else { return nil }
        switch magic {
        case 0xCAFEBABE, 0xCAFEBABF:                 // fat (big-endian header)
            let wide = magic == 0xCAFEBABF
            guard let n = u32(4, big: true), n > 0, n < 16 else { return nil }
            var out: [String] = []
            for i in 0..<Int(n) {
                let o = 8 + i * (wide ? 32 : 20)
                guard let cpu = u32(o, big: true), let sub = u32(o + 4, big: true) else { break }
                out.append(name(cpu, sub))
            }
            return out.isEmpty ? nil : Array(Set(out)).sorted()
        case 0xFEEDFACE, 0xFEEDFACF:                 // thin, big-endian
            guard let cpu = u32(4, big: true), let sub = u32(8, big: true) else { return nil }
            return [name(cpu, sub)]
        case 0xCEFAEDFE, 0xCFFAEDFE:                 // thin, little-endian
            guard let cpu = u32(4, big: false), let sub = u32(8, big: false) else { return nil }
            return [name(cpu, sub)]
        default: return nil
        }
    }
}

/// Reads only the header of a `.cube` file (title, size, domain). Full parsing: `CubeLUT`.
public struct LUTHeader: Sendable, Equatable {
    public var title: String?
    public var size1D: Int?
    public var size3D: Int?
    public var domainMin: [Double]?
    public var domainMax: [Double]?
}

public enum LUTHeaderReader {
    public static func readCubeHeader(at url: URL, maxBytes: Int = 4096) -> LUTHeader? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        guard let d = try? h.read(upToCount: maxBytes), let text = String(data: d, encoding: .utf8) ?? String(data: d, encoding: .isoLatin1) else { return nil }
        var hd = LUTHeader()
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let t = line.split(separator: " ", omittingEmptySubsequences: true)
            guard let key = t.first else { continue }
            switch key {
            case "TITLE": hd.title = line.dropFirst(5).trimmingCharacters(in: CharacterSet(charactersIn: " \"\t"))
            case "LUT_1D_SIZE": hd.size1D = t.count > 1 ? Int(t[1]) : nil
            case "LUT_3D_SIZE": hd.size3D = t.count > 1 ? Int(t[1]) : nil
            case "DOMAIN_MIN": hd.domainMin = t.dropFirst().compactMap { Double($0) }
            case "DOMAIN_MAX": hd.domainMax = t.dropFirst().compactMap { Double($0) }
            default: break
            }
        }
        return hd
    }
}

/// Bounded, non-executing facts about a DCTL file. The code is never compiled or run.
public struct DCTLFacts: Sendable, Equatable {
    public var uiParameterCount: Int
    public var hasTransformFunction: Bool
    public var lineCount: Int
    public var truncated: Bool
}

public enum DCTLReader {
    public static let maxBytes = 256 * 1024
    public static func read(at url: URL) -> DCTLFacts? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        guard let d = try? h.read(upToCount: maxBytes + 1) else { return nil }
        let truncated = d.count > maxBytes
        let text = String(decoding: d.prefix(maxBytes), as: UTF8.self)
        var params = 0, lines = 0, transform = false
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            lines += 1
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("//") { continue }
            if t.contains("DEFINE_UI_PARAMS") { params += 1 }
            if t.contains("transform(") && (t.contains("__DEVICE__") || t.contains("float3")) { transform = true }
        }
        return DCTLFacts(uiParameterCount: params, hasTransformFunction: transform, lineCount: lines, truncated: truncated)
    }
}
