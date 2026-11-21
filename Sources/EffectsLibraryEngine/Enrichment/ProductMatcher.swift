// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Foundation
import EffectsLibraryCore

/// Name normalization and match scoring. Conservative: a wrong association is worse than a missing one, so anything short of a
/// strong match is only ever a proposal.
public enum ProductMatcher {
    /// Lower-case, diacritics folded, version numbers / bundle extensions / "(Disabled)" dropped, punctuation to spaces.
    /// The original name is never changed; this is only for comparison.
    public static func normalize(_ name: String) -> [String] {
        var s = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        for ext in [".ofx.bundle", ".vst3", ".component", ".vst", ".bundle", ".cube", ".dctl", ".3dl"] where s.hasSuffix(ext) { s = String(s.dropLast(ext.count)) }
        s = s.replacingOccurrences(of: "(disabled by gdc)", with: " ")
        let noise: Set<String> = ["plugin", "plug-in", "plug", "in", "ofx", "vst", "vst3", "au", "audio", "unit", "for", "the", "x64", "arm64", "universal", "resolve", "davinci"]
        let tokens = s.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        return tokens.filter { t in !noise.contains(t) && !(t.allSatisfy(\.isNumber) && t.count <= 2) && !isVersion(t) }
    }
    private static func isVersion(_ t: String) -> Bool { t.hasPrefix("v") && t.dropFirst().allSatisfy(\.isNumber) && t.count > 1 }

    public enum Confidence: String, Sendable { case strong, ambiguous, weak }

    public struct Verdict: Sendable, Equatable { public var confidence: Confidence; public var score: Double; public var note: String? }

    /// Compares the installed item against what a page/candidate claims.
    public static func verdict(item: EffectItem, candidateName: String?, candidateProducer: String?) -> Verdict {
        let a = Set(normalize(item.name))
        let b = Set(normalize(candidateName ?? ""))
        guard !a.isEmpty, !b.isEmpty else { return Verdict(confidence: .weak, score: 0, note: "The page does not state a product name.") }
        let j = Double(a.intersection(b).count) / Double(a.union(b).count)
        let vendorOK: Bool? = {
            guard let v = item.vendor, let p = candidateProducer else { return nil }
            let vt = Set(normalize(v)), pt = Set(normalize(p)); guard !vt.isEmpty, !pt.isEmpty else { return nil }
            return !vt.intersection(pt).isEmpty
        }()
        if vendorOK == false { return Verdict(confidence: .ambiguous, score: j * 0.5, note: "The producer on the page differs from the installed vendor.") }
        if j >= 0.99 { return Verdict(confidence: .strong, score: j, note: nil) }
        if j >= 0.6 { return Verdict(confidence: .ambiguous, score: j, note: "The name only partly matches (\(Int(j * 100))%).") }
        return Verdict(confidence: .weak, score: j, note: "The name does not match the installed item.")
    }

    /// Suite vs individual effect: an item that exposes several effects is a package/suite; its cover belongs to the package only.
    public static func isSuite(_ item: EffectItem) -> Bool { item.exposedEffects.count > 1 }
}
