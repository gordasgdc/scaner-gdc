// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Foundation
import CryptoKit

/// Item identity rules (documented in docs/ARCHITECTURE.md §Identity):
/// - id = SHA-256 prefix of `kind | location`, where location is the bundle identifier when known
///   plus the standardized path; a rescan of the same file yields the same id.
/// - Same package in two places = two ids, one shared `duplicateKey` (duplicates, not one item).
/// - A move changes the path, hence the id: the Disabled/Restore journal (Etapa 4) records
///   old id → new id explicitly instead of guessing.
public enum StableID {
    public static func make(kind: ItemKind, bundleIdentifier: String?, path: String) -> String {
        let canonical = (path as NSString).standardizingPath
        let material = "\(kind.rawValue)|\(bundleIdentifier ?? "-")|\(canonical)"
        let digest = SHA256.hash(data: Data(material.utf8))
        return digest.prefix(10).map { String(format: "%02x", $0) }.joined()
    }
}
