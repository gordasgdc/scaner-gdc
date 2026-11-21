// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Foundation

/// Facts read from a producer's page. The page text is DATA: tags are never rendered, entities are decoded, control characters
/// dropped, every field length-capped. Nothing is executed and no sub-resource is loaded.
public struct PageMetadata: Sendable, Equatable {
    public var title: String?
    public var siteName: String?
    public var description: String?
    public var imageURL: URL?
    public var canonicalURL: URL?
}

public enum PageMetadataExtractor {
    public static let maxScan = 256 * 1024
    public static let maxSummary = 280

    public static func extract(html data: Data, baseURL: URL) -> PageMetadata {
        let text = String(decoding: data.prefix(maxScan), as: UTF8.self)
        let head = text.range(of: "</head", options: .caseInsensitive).map { String(text[..<$0.lowerBound]) } ?? text
        var m = PageMetadata()
        var meta: [String: String] = [:]
        for tag in tags(named: "meta", in: head) {
            let a = attributes(tag)
            guard let content = a["content"] else { continue }
            if let k = (a["property"] ?? a["name"])?.lowercased(), meta[k] == nil { meta[k] = content }
        }
        m.title = clean(meta["og:title"] ?? meta["twitter:title"] ?? titleTag(head), max: 120)
        m.siteName = clean(meta["og:site_name"], max: 80)
        m.description = clean(meta["og:description"] ?? meta["description"] ?? meta["twitter:description"], max: maxSummary)
        if let s = meta["og:image"] ?? meta["twitter:image"] { m.imageURL = absolute(s, base: baseURL) }
        for tag in tags(named: "link", in: head) {
            let a = attributes(tag)
            if a["rel"]?.lowercased() == "canonical", let h = a["href"], let u = absolute(h, base: baseURL) { m.canonicalURL = u; break }
        }
        return m
    }

    static func absolute(_ s: String, base: URL) -> URL? {
        guard s.count <= URLPolicy.maxLength, let u = URL(string: decodeEntities(s).trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: base)?.absoluteURL else { return nil }
        if case .success = URLPolicy.validate(u) { return u }
        return nil
    }

    private static func titleTag(_ head: String) -> String? {
        guard let a = head.range(of: "<title", options: .caseInsensitive), let b = head.range(of: ">", range: a.upperBound..<head.endIndex),
              let c = head.range(of: "</title", options: .caseInsensitive, range: b.upperBound..<head.endIndex) else { return nil }
        return String(head[b.upperBound..<c.lowerBound])
    }

    private static func tags(named name: String, in s: String) -> [String] {
        var out: [String] = []; var i = s.startIndex
        while let r = s.range(of: "<\(name)", options: .caseInsensitive, range: i..<s.endIndex) {
            guard let e = tagEnd(s, from: r.upperBound) else { break }
            let after = s[r.upperBound]
            if after == " " || after == "\n" || after == "\t" || after == "\r" || after == "/" { out.append(String(s[r.upperBound..<e])) }
            i = s.index(after: e)
            if out.count > 400 { break }
        }
        return out
    }

    /// Index of the `>` that closes a tag, ignoring any `>` inside quoted attribute values.
    private static func tagEnd(_ s: String, from: String.Index) -> String.Index? {
        var q: Character?; var i = from
        while i < s.endIndex {
            let c = s[i]
            if let open = q { if c == open { q = nil } } else if c == "\"" || c == "'" { q = c } else if c == ">" { return i }
            i = s.index(after: i)
        }
        return nil
    }

    /// Tolerant attribute scanner for `a="x" b='y' c=z` (values with either quote, or bare).
    private static func attributes(_ tag: String) -> [String: String] {
        var out: [String: String] = [:]; let c = Array(tag); var i = 0
        func skipWS() { while i < c.count, c[i].isWhitespace || c[i] == "/" { i += 1 } }
        while i < c.count {
            skipWS(); var name = ""
            while i < c.count, !c[i].isWhitespace, c[i] != "=", c[i] != "/" { name.append(c[i]); i += 1 }
            skipWS()
            var value = ""
            if i < c.count, c[i] == "=" {
                i += 1; skipWS()
                if i < c.count, c[i] == "\"" || c[i] == "'" { let q = c[i]; i += 1; while i < c.count, c[i] != q { value.append(c[i]); i += 1 }; i += 1 }
                else { while i < c.count, !c[i].isWhitespace { value.append(c[i]); i += 1 } }
            }
            if !name.isEmpty, out[name.lowercased()] == nil { out[name.lowercased()] = decodeEntities(value) }
        }
        return out
    }

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var r = s
        for (k, v) in ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " ", "&#x27;": "'"] { r = r.replacingOccurrences(of: k, with: v) }
        return r
    }

    /// Plain text only: markup removed, control characters dropped, whitespace collapsed, length capped.
    public static func clean(_ s: String?, max: Int) -> String? {
        guard var t = s else { return nil }
        t = decodeEntities(t)
        t = t.replacingOccurrences(of: "<(script|style)[^>]*>.*?</\\1\\s*>", with: " ", options: [.regularExpression, .caseInsensitive])
        while let a = t.firstIndex(of: "<"), let b = t[a...].firstIndex(of: ">") { t.removeSubrange(a...b) }
        t = String(t.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) || $0 == " " }.map(Character.init))
        t = t.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        if t.isEmpty { return nil }
        if t.count > max { t = String(t.prefix(max - 1)) + "…" }
        return t
    }
}
