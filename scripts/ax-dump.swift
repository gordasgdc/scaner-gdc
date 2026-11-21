// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
// Dumps the accessibility tree of a running app (by pid) and lists interactive elements without a usable name.
// Usage: swift scripts/ax-dump.swift <pid> > tree.txt     (needs the Accessibility permission of the calling process)
import ApplicationServices
import Foundation
func attr(_ e: AXUIElement, _ a: String) -> AnyObject? { var v: CFTypeRef?; return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v as AnyObject? : nil }
let interactive: Set<String> = ["AXButton", "AXCheckBox", "AXRadioButton", "AXTextField", "AXPopUpButton", "AXMenuButton", "AXSlider", "AXRow", "AXCell", "AXLink", "AXSearchField", "AXComboBox", "AXTextArea"]
var unnamed: [String] = [], counts: [String: Int] = [:], lines: [String] = []
func walk(_ e: AXUIElement, _ depth: Int) {
    let role = attr(e, "AXRole") as? String ?? "?"
    let name = [attr(e, "AXTitle"), attr(e, "AXDescription"), attr(e, "AXValue"), attr(e, "AXHelp")].compactMap { $0 as? String }.first { !$0.isEmpty } ?? ""
    counts[role, default: 0] += 1
    if depth < 14 { lines.append(String(repeating: "  ", count: depth) + role + (name.isEmpty ? "" : " “\(name.prefix(70))”")) }
    if interactive.contains(role), name.isEmpty {
        // Rows/cells may be named by their children; accept if any descendant text exists.
        var hasText = false
        func scan(_ x: AXUIElement, _ d: Int) { if d > 4 { return }; for c in (attr(x, "AXChildren") as? [AXUIElement]) ?? [] { if let t = attr(c, "AXValue") as? String, !t.isEmpty { hasText = true }; if let t = attr(c, "AXTitle") as? String, !t.isEmpty { hasText = true }; scan(c, d + 1) } }
        scan(e, 0)
        if !hasText { unnamed.append("\(role) at depth \(depth)") }
    }
    if depth > 30 { return }
    for c in (attr(e, "AXChildren") as? [AXUIElement]) ?? [] { walk(c, depth + 1) }
}
let app = AXUIElementCreateApplication(pid_t(CommandLine.arguments[1])!)
for w in (attr(app, "AXWindows") as? [AXUIElement]) ?? [] { walk(w, 0) }
print(lines.joined(separator: "\n"))
print("\n== role counts: \(counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")
print("== interactive elements without a name: \(unnamed.count)"); unnamed.prefix(30).forEach { print("  - \($0)") }
