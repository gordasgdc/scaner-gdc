// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Foundation

/// Minimal ZIP writer (STORE method, no compression, no zip64): enough for small inspectable diagnostic packages.
public struct ZipWriter {
    private var body = Data()
    private var central = Data()
    private var count = 0
    private static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i); for _ in 0..<8 { c = c & 1 == 1 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }; return c }

    public init() {}

    public static func crc32(_ d: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in d { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }

    public mutating func add(path: String, data: Data, date: Date = Date()) {
        let name = Data(path.utf8)
        let (dt, dd) = Self.dos(date)
        let crc = Self.crc32(data)
        let offset = UInt32(body.count)
        var h = Data()
        h.le32(0x04034b50); h.le16(20); h.le16(0x0800); h.le16(0); h.le16(dt); h.le16(dd)
        h.le32(crc); h.le32(UInt32(data.count)); h.le32(UInt32(data.count)); h.le16(UInt16(name.count)); h.le16(0)
        body += h; body += name; body += data
        var c = Data()
        c.le32(0x02014b50); c.le16(20); c.le16(20); c.le16(0x0800); c.le16(0); c.le16(dt); c.le16(dd)
        c.le32(crc); c.le32(UInt32(data.count)); c.le32(UInt32(data.count)); c.le16(UInt16(name.count))
        c.le16(0); c.le16(0); c.le16(0); c.le16(0); c.le32(0); c.le32(offset)
        central += c; central += name; count += 1
    }

    public func finish() -> Data {
        var end = Data()
        end.le32(0x06054b50); end.le16(0); end.le16(0); end.le16(UInt16(count)); end.le16(UInt16(count))
        end.le32(UInt32(central.count)); end.le32(UInt32(body.count)); end.le16(0)
        return body + central + end
    }

    private static func dos(_ d: Date) -> (UInt16, UInt16) {
        let c = Calendar(identifier: .gregorian).dateComponents(in: .current, from: d)
        let y = max((c.year ?? 1980) - 1980, 0)
        return (UInt16(((c.hour ?? 0) << 11) | ((c.minute ?? 0) << 5) | ((c.second ?? 0) / 2)),
                UInt16((y << 9) | ((c.month ?? 1) << 5) | (c.day ?? 1)))
    }
}

private extension Data {
    mutating func le16(_ v: UInt16) { append(UInt8(v & 0xFF)); append(UInt8(v >> 8)) }
    mutating func le32(_ v: UInt32) { for i in 0..<4 { append(UInt8((v >> (8 * UInt32(i))) & 0xFF)) } }
}
