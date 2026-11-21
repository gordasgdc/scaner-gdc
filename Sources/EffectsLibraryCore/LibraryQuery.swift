// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Foundation

public enum SortKey: String, CaseIterable, Sendable, Codable {
    case name, kind, vendor, modified

    public var title: String {
        switch self {
        case .name: "Name"
        case .kind: "Type"
        case .vendor: "Vendor"
        case .modified: "Modified"
        }
    }
}

/// Pure, deterministic filtering + sorting. No UI, no filesystem.
public struct LibraryQuery: Sendable, Equatable {
    public var searchText = ""
    /// Empty = all kinds.
    public var kinds: Set<ItemKind> = []
    /// `nil` = all sources.
    public var sourceID: String?
    /// `nil` = all vendors; `Self.unknownVendor` selects items without vendor.
    public var vendor: String?
    public var onlyDuplicates = false
    /// `nil` = both states.
    public var state: ItemState?
    public var sortKey: SortKey = .name
    public var ascending = true

    public static let unknownVendor = "\u{0}unknown"

    public init() {}

    public func matches(_ item: EffectItem, duplicateKeys: Set<String>) -> Bool {
        matches(item, duplicateKeys: duplicateKeys, needle: searchText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func matches(_ item: EffectItem, duplicateKeys: Set<String>, needle: String) -> Bool {
        if !kinds.isEmpty, !kinds.contains(item.kind) { return false }
        if let sourceID, item.sourceID != sourceID { return false }
        if let vendor {
            if vendor == Self.unknownVendor { if item.vendor != nil { return false } }
            else if item.vendor != vendor { return false }
        }
        if let state, item.state != state { return false }
        if onlyDuplicates, !(item.state == .active && duplicateKeys.contains(item.duplicateKey)) { return false }
        if !needle.isEmpty {
            let hay = ([item.name, item.vendor ?? "", item.path, item.bundleIdentifier ?? ""] + item.exposedEffects)
            if !hay.contains(where: { $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }) {
                return false
            }
        }
        return true
    }

    public func apply(to items: [EffectItem]) -> [EffectItem] {
        let dups = onlyDuplicates ? Self.duplicateKeys(in: items) : []
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = items.filter { matches($0, duplicateKeys: dups, needle: needle) }
        return filtered.sorted { a, b in
            let r = compare(a, b)
            if r != .orderedSame { return ascending ? r == .orderedAscending : r == .orderedDescending }
            return a.id < b.id // total order: deterministic regardless of input order
        }
    }

    private func compare(_ a: EffectItem, _ b: EffectItem) -> ComparisonResult {
        func text(_ x: String, _ y: String) -> ComparisonResult {
            x.compare(y, options: [.caseInsensitive, .diacriticInsensitive, .numeric])
        }
        switch sortKey {
        case .name: return text(a.name, b.name)
        case .kind:
            let ia = ItemKind.allCases.firstIndex(of: a.kind)!, ib = ItemKind.allCases.firstIndex(of: b.kind)!
            if ia != ib { return ia < ib ? .orderedAscending : .orderedDescending }
            return text(a.name, b.name)
        case .vendor:
            // Unknown vendors sort last in ascending order.
            switch (a.vendor, b.vendor) {
            case let (x?, y?): let r = text(x, y); return r == .orderedSame ? text(a.name, b.name) : r
            case (nil, nil): return text(a.name, b.name)
            case (nil, _): return .orderedDescending
            case (_, nil): return .orderedAscending
            }
        case .modified:
            switch (a.modified, b.modified) {
            case let (x?, y?): return x == y ? text(a.name, b.name) : (x < y ? .orderedAscending : .orderedDescending)
            case (nil, nil): return text(a.name, b.name)
            case (nil, _): return .orderedDescending
            case (_, nil): return .orderedAscending
            }
        }
    }

    /// Keys occurring on more than one distinct item.
    public static func duplicateKeys(in items: [EffectItem]) -> Set<String> {
        var seen: [String: Int] = [:]
        for i in items where i.state == .active { seen[i.duplicateKey, default: 0] += 1 }
        return Set(seen.filter { $0.value > 1 }.keys)
    }

    public static func vendors(in items: [EffectItem]) -> [String] {
        Array(Set(items.compactMap(\.vendor))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
