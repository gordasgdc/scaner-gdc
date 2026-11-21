// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Foundation

/// Where a cover image came from. Never confused with the real preview (LUT render) or the package icon.
public enum CoverOrigin: String, Sendable, Codable, Hashable { case userLocal, officialPage }

/// What is known about the right to use an image. Unknown is never promoted to "allowed".
public enum ImageRights: String, Sendable, Codable, Hashable {
    /// Picked by the user from their own files.
    case userSupplied
    /// Published by the producer's page as its own link-preview image (Open Graph); used locally only, never redistributed.
    case pageDeclaredPreview
}

public enum RecordStatus: String, Sendable, Codable, Hashable {
    case confirmed   // the user associated or confirmed it
    case proposed    // found automatically or ambiguous: waits for the user
    case rejected    // the user rejected the proposal: never proposed again until reset
}

public struct CoverImageRef: Sendable, Codable, Hashable {
    public var fileName: String            // <sha256>.png in the covers folder (user covers and fetched covers live in different folders)
    public var origin: CoverOrigin
    public var rights: ImageRights
    public var sourceURL: String?          // where it was fetched from (nil for local files)
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var obtainedAt: Date
    public init(fileName: String, origin: CoverOrigin, rights: ImageRights, sourceURL: String?, pixelWidth: Int, pixelHeight: Int, obtainedAt: Date = Date()) {
        self.fileName = fileName; self.origin = origin; self.rights = rights; self.sourceURL = sourceURL
        self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight; self.obtainedAt = obtainedAt
    }
}

/// Online enrichment of one *product* (not one file location). Kept apart from the scanned metadata: it never overwrites
/// the installed version, vendor or bundle identifier. Keyed by `ProductKey`, which does not contain a path, so it survives
/// rescans and moves (Disable/Restore).
public struct ProductRecord: Sendable, Codable, Hashable, Identifiable {
    public var id: String { key }
    public let key: String
    public var status: RecordStatus
    public var productName: String?        // as stated by the source
    public var producer: String?
    public var summary: String?            // short, factual, length-capped
    public var officialURL: String?
    public var sourceURL: String?          // page the details were read from
    public var retrievedAt: Date?
    public var cover: CoverImageRef?
    public var proposedImageURL: String?   // offered for confirmation; downloaded only after the user accepts
    public var ambiguity: String?          // why this is only a proposal
    public var userChoseURL = false
    public var userChoseImage = false
    public var updatedAt: Date
    public init(key: String, status: RecordStatus = .proposed, updatedAt: Date = Date()) { self.key = key; self.status = status; self.updatedAt = updatedAt }
}

public enum ProductKey {
    /// Path-independent identity of a product: same kind and bundle identifier (or normalized name).
    public static func make(for item: EffectItem) -> String { item.duplicateKey }
}
