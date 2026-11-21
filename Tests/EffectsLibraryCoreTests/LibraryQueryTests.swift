// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Testing
import Foundation
@testable import EffectsLibraryCore

@Suite struct LibraryQueryTests {
    let items = MockData.items

    @Test func mockCoversRequiredEdgeCases() {
        #expect(items.contains { $0.name.count > 60 }, "long name")
        #expect(items.contains { $0.vendor == nil && $0.version == nil && $0.modified != nil }, "missing metadata")
        #expect(!LibraryQuery.duplicateKeys(in: items).isEmpty, "duplicates")
        #expect(MockData.sources.contains { if case .unavailable = $0.availability { true } else { false } }, "unavailable source")
        #expect(MockData.sources.contains { $0.availability == .notScanned }, "not scanned source")
        #expect(Set(items.map(\.kind)) == Set(ItemKind.allCases), "every kind present")
    }

    @Test func idsAreUniqueAndStable() {
        #expect(Set(items.map(\.id)).count == items.count)
        // Rebuilding the same item yields the same id (stable across rescans).
        let a = items[0]
        let b = EffectItem(name: "renamed", kind: a.kind, sourceID: a.sourceID, path: a.path, bundleIdentifier: a.bundleIdentifier)
        #expect(a.id == b.id)
    }

    @Test func duplicatesShareKeyButNotId() {
        let reverb = items.filter { $0.kind == .vst3 && $0.name == "Reverb Chamber" }
        #expect(reverb.count == 2)
        #expect(reverb[0].duplicateKey == reverb[1].duplicateKey)
        #expect(reverb[0].id != reverb[1].id)
        var q = LibraryQuery(); q.onlyDuplicates = true
        #expect(q.apply(to: items).allSatisfy { $0.name == "Reverb Chamber" })
    }

    @Test func searchIsCaseAndDiacriticInsensitiveAndCoversEffects() {
        var q = LibraryQuery(); q.searchText = "HALATION"
        #expect(q.apply(to: items).map(\.name) == ["Halation Pro"])
        q.searchText = "veiling" // exposed effect of the long-named bundle
        #expect(q.apply(to: items).count == 1)
        q.searchText = "no-such-thing"
        #expect(q.apply(to: items).isEmpty)
    }

    @Test func kindSourceVendorFilters() {
        var q = LibraryQuery(); q.kinds = [.dctl]
        #expect(q.apply(to: items).allSatisfy { $0.kind == .dctl })
        q = LibraryQuery(); q.sourceID = "vst3-user"
        #expect(q.apply(to: items).allSatisfy { $0.sourceID == "vst3-user" })
        q = LibraryQuery(); q.vendor = LibraryQuery.unknownVendor
        let unknown = q.apply(to: items)
        #expect(!unknown.isEmpty && unknown.allSatisfy { $0.vendor == nil })
        q.vendor = "Echoform"
        #expect(q.apply(to: items).allSatisfy { $0.vendor == "Echoform" })
    }

    @Test func sortingIsDeterministicAndPutsUnknownLast() {
        var q = LibraryQuery(); q.sortKey = .vendor
        let asc = q.apply(to: items)
        #expect(asc.last?.vendor == nil)
        #expect(q.apply(to: items.reversed()).map(\.id) == asc.map(\.id), "input order must not matter")
        q.ascending = false
        #expect(q.apply(to: items).map(\.id) != asc.map(\.id))

        q = LibraryQuery(); q.sortKey = .modified
        let byDate = q.apply(to: items).compactMap(\.modified)
        #expect(byDate == byDate.sorted())

        q = LibraryQuery(); q.sortKey = .kind
        let kinds = q.apply(to: items).map { ItemKind.allCases.firstIndex(of: $0.kind)! }
        #expect(kinds == kinds.sorted())
    }

    @Test func naturalNameOrdering() {
        let mk = { (n: String) in EffectItem(name: n, kind: .lut, sourceID: "s", path: "/x/\(n).cube") }
        let q = LibraryQuery()
        #expect(q.apply(to: [mk("Look 10"), mk("Look 2"), mk("Look 1")]).map(\.name) == ["Look 1", "Look 2", "Look 10"])
    }

    @Test func emptyInventoryAndEmptyQuery() {
        #expect(LibraryQuery().apply(to: []).isEmpty)
        #expect(LibraryQuery().apply(to: items).count == items.count)
    }
}
