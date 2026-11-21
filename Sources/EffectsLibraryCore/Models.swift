// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Foundation

/// Kinds of resources the library inventories (Etapa 1: mock data only).
public enum ItemKind: String, CaseIterable, Sendable, Codable, Hashable {
    case ofx, lut, dctl, vst3, audioUnit, vst

    /// Declaration order is the sidebar order.
    public var title: String {
        switch self {
        case .ofx: "OFX"
        case .lut: "LUT"
        case .dctl: "DCTL"
        case .vst3: "VST3"
        case .audioUnit: "Audio Units"
        case .vst: "VST"
        }
    }

    public var isAudio: Bool { self == .vst3 || self == .audioUnit || self == .vst }
}

/// What the app can actually state about a source. Never "empty" when it was not readable.
public enum SourceAvailability: Sendable, Hashable, Codable {
    case available
    /// The folder exists in principle but could not be read (permission, I/O error, lost access).
    case unavailable(reason: String)
    /// A standard location that does not exist on this Mac (normal; not an error).
    case missing
    case notScanned
}

/// Where a source definition comes from.
public enum SourceOrigin: String, Sendable, Hashable, Codable {
    case standard, resolve, custom, disabledStore, mock
}

/// Provenance of the whole inventory shown in the UI.
public enum InventoryOrigin: String, Sendable, Hashable, Codable {
    case mock, live, lastKnown
}

public enum ItemState: String, Sendable, Hashable, Codable { case active, disabled }

/// What kind of preview an item can have (declared limits; never a fake render).
public enum PreviewSupport: String, Sendable, Hashable, Codable {
    case lutCube       // rendered from a parsed .cube LUT on a synthetic reference
    case bundleIcon    // icon resource extracted from the bundle (not a render of the effect)
    case none          // metadata / generic fallback only (DCTL, unsupported LUT formats, bundles without icon)
}

public struct LibrarySource: Sendable, Hashable, Identifiable, Codable {
    public let id: String
    public var displayName: String
    /// Display path. In the mock it is illustrative; the product resolves the user directory dynamically.
    public var path: String
    public var kinds: Set<ItemKind>
    public var availability: SourceAvailability
    public var origin: SourceOrigin
    public var lastScan: Date?
    /// Non-fatal read problems during the last scan (capped); the source is still listed as available.
    public var warnings: [String] = []
    /// For disabled stores: the active source they belong to.
    public var parentSourceID: String?

    public init(id: String, displayName: String, path: String, kinds: Set<ItemKind>, availability: SourceAvailability,
                origin: SourceOrigin = .mock, lastScan: Date? = nil, warnings: [String] = [], parentSourceID: String? = nil) {
        self.warnings = warnings; self.parentSourceID = parentSourceID
        self.id = id; self.displayName = displayName; self.path = path
        self.kinds = kinds; self.availability = availability; self.origin = origin; self.lastScan = lastScan
    }
}

/// An installed package (bundle or file), not an individual effect.
public struct EffectItem: Sendable, Hashable, Identifiable, Codable {
    /// Stable across rescans: see `StableID`.
    public let id: String
    public var name: String
    public var kind: ItemKind
    public var sourceID: String
    public var path: String
    /// Unknown stays `nil`; nothing is invented.
    public var vendor: String?
    public var version: String?
    public var bundleIdentifier: String?
    public var modified: Date?
    public var sizeBytes: Int64?
    /// Effects the package exposes to a host (distinct from the package itself).
    public var exposedEffects: [String]
    /// Architectures read from metadata; `nil` = unknown. Never a claim of host compatibility.
    public var architectures: [String]?
    public var state: ItemState = .active
    /// For disabled items: where Restore returns it (from the journal); `nil` if unknown.
    public var originalPath: String?
    /// Format-specific facts read from metadata (e.g. LUT size, DCTL parameter count). Unknown = absent.
    public var details: [String: String] = [:]
    public var previewSupport: PreviewSupport = .none
    /// Why no preview is available (shown in the inspector).
    public var previewNote: String?

    public init(name: String, kind: ItemKind, sourceID: String, path: String,
                vendor: String? = nil, version: String? = nil, bundleIdentifier: String? = nil,
                modified: Date? = nil, sizeBytes: Int64? = nil, exposedEffects: [String] = [],
                architectures: [String]? = nil, state: ItemState = .active, originalPath: String? = nil,
                details: [String: String] = [:], previewSupport: PreviewSupport = .none, previewNote: String? = nil) {
        self.state = state; self.originalPath = originalPath; self.details = details
        self.previewSupport = previewSupport; self.previewNote = previewNote
        self.name = name; self.kind = kind; self.sourceID = sourceID; self.path = path
        self.vendor = vendor; self.version = version; self.bundleIdentifier = bundleIdentifier
        self.modified = modified; self.sizeBytes = sizeBytes
        self.exposedEffects = exposedEffects; self.architectures = architectures
        self.id = StableID.make(kind: kind, bundleIdentifier: bundleIdentifier, path: path)
    }

    /// Items sharing this key are *duplicates* (same thing in several places); they keep distinct ids.
    public var duplicateKey: String {
        "\(kind.rawValue)|\((bundleIdentifier ?? name).lowercased())"
    }

    public var fileName: String { (path as NSString).lastPathComponent }
}
