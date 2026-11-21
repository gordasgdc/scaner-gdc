// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Foundation
import CryptoKit

/// Removes secrets and (optionally) anonymizes personal paths. Used by the logger and by the support export.
public struct Redactor: Sendable {
    public enum PathMode: Sendable {
        /// Local log: only the home directory is abbreviated to `~`.
        case local
        /// Support package: user names and volume names are removed, user/volume paths are hashed.
        case support
        /// Support package where the owner explicitly chose to include paths.
        case includePaths
    }

    public var homePath: String
    public var pathMode: PathMode

    public init(homePath: String = NSHomeDirectory(), pathMode: PathMode = .local) {
        self.homePath = homePath; self.pathMode = pathMode
    }

    private static let secretKeys = "password|passwd|pwd|token|secret|api[_-]?key|apikey|license|licence|serial|authorization|bearer|credential"
    // key=value / key: value / "key":"value"
    private static let kv = try! NSRegularExpression(pattern: "(?i)(\"?[a-z_\\-]*(?:\(secretKeys))[a-z_\\-]*\"?\\s*[:=]\\s*)(\"[^\"]*\"|'[^']*'|[^\\s,;&\"']+)")
    private static let bearer = try! NSRegularExpression(pattern: "(?i)\\bbearer\\s+[A-Za-z0-9._\\-]+")
    private static let email = try! NSRegularExpression(pattern: "[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}")
    private static let longToken = try! NSRegularExpression(pattern: "\\b[A-Fa-f0-9]{32,}\\b|\\b[A-Za-z0-9+/_\\-]{40,}={0,2}")
    // Paths may contain spaces: run until a quote, bracket, comma, semicolon, arrow, line end or ": ". Privacy first: over-matching trailing words is acceptable.
    private static let path = try! NSRegularExpression(pattern: "((?:/(?:Users|Volumes)/|~/)(?:(?!: | /)[^\"'<>,;\\n\\r\\t\u{2192}])+)")

    public func redact(_ text: String) -> String {
        var s = text
        s = Self.replace(Self.bearer, in: s) { _ in "Bearer <redacted>" }
        s = Self.replace(Self.kv, in: s) { m in "\(m.group(1))<redacted>" }
        s = Self.replace(Self.email, in: s) { _ in "<email>" }
        s = Self.replace(Self.longToken, in: s) { _ in "<redacted-token>" }
        switch pathMode {
        case .local:
            if !homePath.isEmpty, homePath != "/" { s = s.replacingOccurrences(of: homePath, with: "~") }
        case .includePaths:
            break
        case .support:
            if !homePath.isEmpty, homePath != "/" { s = s.replacingOccurrences(of: homePath, with: "~") }
            s = Self.replace(Self.path, in: s) { m in Self.anonymize(m.group(1)) }
        }
        return s
    }

    /// `/Users/<name>/rest` → `/Users/<user>/<h8>.ext`, `/Volumes/<vol>/rest` → `/Volumes/<vol-h8>/<h8>.ext` (extension kept).
    static func anonymize(_ p: String) -> String {
        func h(_ x: String) -> String { SHA256.hash(data: Data(x.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined() }
        if p.hasPrefix("~/") {
            let rest = String(p.dropFirst(2)); guard !rest.isEmpty else { return p }
            let ext = (rest as NSString).pathExtension
            return "~/" + h(rest) + (ext.isEmpty ? "" : "." + ext)
        }
        let parts = p.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2 else { return p }
        let rest = parts.dropFirst(2).joined(separator: "/")
        let ext = (rest as NSString).pathExtension
        let leaf = rest.isEmpty ? "" : "/" + h(rest) + (ext.isEmpty ? "" : "." + ext)
        return parts[0] == "Users" ? "/Users/<user>\(leaf)" : "/Volumes/<vol-\(h(parts[1]))>\(leaf)"
    }

    private struct Match { let source: String; let result: NSTextCheckingResult
        func group(_ i: Int) -> String { (source as NSString).substring(with: result.range(at: i)) } }

    private static func replace(_ re: NSRegularExpression, in s: String, _ f: (Match) -> String) -> String {
        let ns = s as NSString
        var out = "", last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            out += f(Match(source: s, result: m))
            last = m.range.location + m.range.length
        }
        return out + ns.substring(from: last)
    }
}
