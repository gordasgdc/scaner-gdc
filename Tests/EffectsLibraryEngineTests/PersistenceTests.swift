// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Testing
import Foundation
import EffectsLibraryCore
import EffectsLibraryEngine
import EffectsLibraryTestSupport

@Suite struct PersistenceTests {
    @Test func inventoryRoundTripAndAtomicSave() throws {
        let root = try SyntheticFixtures.workRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let store = JSONStore<InventorySnapshot>(url: root.appendingPathComponent("inv.json"))
        #expect(try store.loadValidated() == nil)
        let snap = InventorySnapshot(sources: MockData.sources, items: MockData.items)
        try store.save(snap)
        let back = try #require(try store.loadValidated())
        #expect(back.items == MockData.items); #expect(back.sources == MockData.sources)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.contains("tmp") || $0.hasPrefix(".") }.isEmpty)
    }
    @Test func corruptFileIsMovedAsideNotOverwritten() throws {
        let root = try SyntheticFixtures.workRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("inv.json"); try Data("{broken".utf8).write(to: url)
        let store = JSONStore<InventorySnapshot>(url: url)
        #expect(throws: StoreError.self) { try store.loadValidated() }
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.contains("corrupt") })
        #expect(try store.loadValidated() == nil)
    }
    @Test func newerSchemaIsRefusedNotMisread() throws {
        let root = try SyntheticFixtures.workRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let store = JSONStore<SourcesFile>(url: root.appendingPathComponent("s.json"))
        var f = SourcesFile(); f.schemaVersion = 99; try store.save(f)
        #expect(throws: StoreError.unsupportedSchema(found: 99, supported: SourcesFile.currentSchema)) { try store.loadValidated() }
    }
    @Test func customSourceIDIsDeterministic() {
        let a = CustomSourceRecord(path: "/x/y", kinds: [.lut], bookmark: nil), b = CustomSourceRecord(path: "/x/y", kinds: [.lut], bookmark: nil)
        #expect(a.id == b.id)
    }
}
