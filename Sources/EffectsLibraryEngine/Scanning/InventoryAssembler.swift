// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Foundation
import EffectsLibraryCore

/// Builds the list of roots to scan (standard + custom + the Disabled stores) and turns scan results into inventory.
public enum InventoryAssembler {
    public static func descriptors(standard: [SourceDescriptor], custom: [CustomSourceRecord], disabledOverride: URL?) -> [SourceDescriptor] {
        let customDesc = custom.map { SourceDescriptor(id: $0.id, displayName: $0.displayName, url: URL(fileURLWithPath: $0.path, isDirectory: true), kinds: $0.kinds, origin: .custom) }
        let active = standard + customDesc
        let stores = active.map { s in
            SourceDescriptor(id: s.id + ".disabled", displayName: s.displayName + " (disabled)",
                             url: DisabledLocations.root(for: s, override: disabledOverride), kinds: s.kinds, origin: .disabledStore, disabledOf: s.id)
        }
        return active + stores
    }

    public static func assemble(_ results: [SourceScanResult], journal: OperationJournal?, now: Date = Date()) -> (sources: [LibrarySource], items: [EffectItem]) {
        var sources: [LibrarySource] = [], items: [EffectItem] = []
        for r in results.sorted(by: { $0.descriptor.displayName.localizedStandardCompare($1.descriptor.displayName) == .orderedAscending }) {
            let d = r.descriptor
            // An empty, missing disabled store is not interesting to show as a source.
            if d.disabledOf != nil, r.items.isEmpty { continue }
            sources.append(LibrarySource(id: d.id, displayName: d.displayName, path: d.url.path, kinds: d.kinds, availability: r.availability,
                                         origin: d.origin, lastScan: now, warnings: r.warnings, parentSourceID: d.disabledOf))
            for var it in r.items {
                if d.disabledOf != nil { it.originalPath = journal?.disabledRecord(atPath: it.path)?.originalPath }
                items.append(it)
            }
        }
        return (sources, items)
    }
}
