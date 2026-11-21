// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Foundation

/// Keyboard selection movement over the *visible* list (pure, testable).
public enum SelectionNavigation {
    /// Moves by `delta` positions, clamped. With no (or hidden) current selection: first for forward, last for backward.
    public static func move(current: String?, in ids: [String], by delta: Int) -> String? {
        guard !ids.isEmpty else { return nil }
        guard let current, let idx = ids.firstIndex(of: current) else { return delta >= 0 ? ids.first : ids.last }
        return ids[min(max(idx + delta, 0), ids.count - 1)]
    }

    /// Selection survives a filter change only if the item is still visible.
    public static func reconcile(current: String?, visible ids: [String]) -> String? {
        guard let current, ids.contains(current) else { return nil }
        return current
    }
}
