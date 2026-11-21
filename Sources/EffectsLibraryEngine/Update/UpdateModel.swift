// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Foundation

/// What the updater trusts and where it looks. Production values are fixed in code; nothing here is read from the environment or user data.
public struct UpdateConfig: Sendable {
    public let manifestURL: URL
    /// Downloads must start with this prefix (https only). Redirects are validated separately.
    public let downloadPrefix: String
    public let bundleIdentifier: String
    public let teamIdentifier: String
    public let requireStapledTicket: Bool
    public init(manifestURL: URL, downloadPrefix: String, bundleIdentifier: String, teamIdentifier: String, requireStapledTicket: Bool = true) {
        self.manifestURL = manifestURL; self.downloadPrefix = downloadPrefix; self.bundleIdentifier = bundleIdentifier
        self.teamIdentifier = teamIdentifier; self.requireStapledTicket = requireStapledTicket
    }
    public static let production = UpdateConfig(
        manifestURL: URL(string: "https://gordasgdc.github.io/scaner-gdc/update.json")!,
        downloadPrefix: "https://github.com/gordasgdc/scaner-gdc/releases/download/",
        bundleIdentifier: "dev.gordas.GDCEffectsLibrary", teamIdentifier: "8AR6XP8MG7")
}

/// update.json. Field names and string-typed version/build follow the platform's published format (old readers decode strictly; fields are only ever added).
public struct UpdateManifest: Decodable, Sendable, Equatable {
    public let version: String
    public let build: String?
    public let changes: String?
    public let mandatory: Bool
    public let downloadURL: String
    public let sha256: String?
    public let size: Int64?
    public let minOS: String?
    enum CodingKeys: String, CodingKey { case version, build, changes, mandatory, sha256, size; case downloadURL = "download_url"; case minOS = "min_os" }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        version = try c.decode(String.self, forKey: .version)
        build = try? c.decodeIfPresent(String.self, forKey: .build)
        changes = try? c.decodeIfPresent(String.self, forKey: .changes)
        mandatory = (try? c.decodeIfPresent(Bool.self, forKey: .mandatory)) ?? false
        if let s = try? c.decode(String.self, forKey: .downloadURL) { downloadURL = s }
        else if let m = try? c.decode([String: String].self, forKey: .downloadURL), let s = m["mac"] { downloadURL = s }   // tolerant, as the platform's readers are
        else { throw DecodingError.keyNotFound(CodingKeys.downloadURL, .init(codingPath: [], debugDescription: "download_url")) }
        sha256 = try? c.decodeIfPresent(String.self, forKey: .sha256)
        size = try? c.decodeIfPresent(Int64.self, forKey: .size)
        minOS = try? c.decodeIfPresent(String.self, forKey: .minOS)
    }
}

public struct UpdateOffer: Sendable, Equatable {
    public let version: String, changes: String, downloadURL: URL, sha256: String?, size: Int64?, mandatory: Bool
}

public enum UpdateCheckResult: Sendable, Equatable {
    case available(UpdateOffer)
    case upToDate(installed: String, published: String)
    /// Distinct from "up to date": we do not know.
    case failed(UpdateFailure)
}

public enum UpdateFailure: Error, Sendable, Equatable, CustomStringConvertible {
    case offline, timeout, http(Int), invalidManifest(String), untrustedDownloadURL, prerelease(String), osTooOld(String)
    case diskSpace(needed: Int64, available: Int64)
    case checksumMismatch, notAnAppImage(String), identity(String), signature(String), notNewer(installed: String, offered: String), versionMismatch(expected: String, found: String)
    case notInstallable(String), installFailed(String, rolledBack: Bool), cancelled, other(String)
    public var description: String {
        switch self {
        case .offline: "No internet connection."
        case .timeout: "The update server did not answer in time."
        case .http(let c): "The update server answered with status \(c)."
        case .invalidManifest(let m): "The update information is not valid (\(m))."
        case .untrustedDownloadURL: "The update points to an address this app does not trust; it was not downloaded."
        case .prerelease(let v): "Version \(v) is a pre-release and is not offered."
        case .osTooOld(let v): "The update needs macOS \(v) or later."
        case .diskSpace(let n, let a): "Not enough free space: about \(ByteCountFormatter.string(fromByteCount: n, countStyle: .file)) needed, \(ByteCountFormatter.string(fromByteCount: a, countStyle: .file)) available."
        case .checksumMismatch: "The downloaded file is damaged (checksum mismatch). Nothing was installed."
        case .notAnAppImage(let m): "The download is not the expected app package (\(m)). Nothing was installed."
        case .identity(let m): "The downloaded app does not have the expected identity (\(m)). Nothing was installed."
        case .signature(let m): "The downloaded app failed signature verification (\(m)). Nothing was installed."
        case .notNewer(let i, let o): "The offered version \(o) is not newer than the installed \(i); nothing was installed."
        case .versionMismatch(let e, let f): "The downloaded app is version \(f) but \(e) was announced. Nothing was installed."
        case .notInstallable(let m): "This copy cannot be updated in place: \(m)"
        case .installFailed(let m, let rb): "The update could not be installed (\(m))." + (rb ? " The previous version was restored." : "")
        case .cancelled: "Cancelled. Nothing was changed."
        case .other(let m): m
        }
    }
}

public enum SemVer {
    /// "0.6.0" -> [0,6,0]; a leading "v" is ignored; any "-suffix" marks a pre-release.
    public static func parse(_ s: String) -> (core: [Int], pre: Bool)? {
        var t = s.trimmingCharacters(in: .whitespaces); if t.lowercased().hasPrefix("v") { t.removeFirst() }
        let pre = t.contains("-")
        let core = t.split(separator: "-", maxSplits: 1).first.map(String.init) ?? t
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 4 else { return nil }
        var out: [Int] = []; for p in parts { guard let n = Int(p), n >= 0 else { return nil }; out.append(n) }
        return (out, pre)
    }
    public static func compare(_ a: [Int], _ b: [Int]) -> Int {
        for i in 0..<max(a.count, b.count) { let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0; if x != y { return x > y ? 1 : -1 } }
        return 0
    }
}
