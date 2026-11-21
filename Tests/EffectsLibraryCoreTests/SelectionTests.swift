// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Testing
@testable import EffectsLibraryCore

@Suite struct SelectionTests {
    let ids = ["a", "b", "c", "d"]
    @Test func movesAndClamps() {
        #expect(SelectionNavigation.move(current: "b", in: ids, by: 1) == "c")
        #expect(SelectionNavigation.move(current: "d", in: ids, by: 1) == "d")
        #expect(SelectionNavigation.move(current: "a", in: ids, by: -3) == "a")
        #expect(SelectionNavigation.move(current: "a", in: ids, by: 2) == "c")
    }
    @Test func noSelectionStartsAtEdge() {
        #expect(SelectionNavigation.move(current: nil, in: ids, by: 1) == "a")
        #expect(SelectionNavigation.move(current: nil, in: ids, by: -1) == "d")
        #expect(SelectionNavigation.move(current: "gone", in: ids, by: 1) == "a")
        #expect(SelectionNavigation.move(current: "a", in: [], by: 1) == nil)
    }
    @Test func reconcileDropsHidden() {
        #expect(SelectionNavigation.reconcile(current: "b", visible: ids) == "b")
        #expect(SelectionNavigation.reconcile(current: "z", visible: ids) == nil)
        #expect(SelectionNavigation.reconcile(current: nil, visible: ids) == nil)
    }
}
