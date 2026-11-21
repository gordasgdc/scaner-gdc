// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Foundation
import EffectsLibraryCore

/// A folder to scan, with the kinds of resources to look for in it.
public struct SourceDescriptor: Sendable, Hashable, Identifiable {
    public var id: String
    public var displayName: String
    public var url: URL
    public var kinds: Set<ItemKind>
    public var origin: SourceOrigin
    /// Items found here are `ItemState.disabled` (a disabled store).
    public var disabledOf: String?

    public init(id: String, displayName: String, url: URL, kinds: Set<ItemKind>, origin: SourceOrigin, disabledOf: String? = nil) {
        self.id = id; self.displayName = displayName; self.url = url; self.kinds = kinds; self.origin = origin; self.disabledOf = disabledOf
    }
    public var canonicalPath: String { url.resolvingSymlinksInPath().standardizedFileURL.path }
}

/// The documented standard locations. The user's home is resolved dynamically; nothing is assumed to exist.
public enum StandardSources {
    public static func all(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [SourceDescriptor] {
        func sys(_ p: String) -> URL { URL(fileURLWithPath: p, isDirectory: true) }
        func usr(_ p: String) -> URL { home.appendingPathComponent(p, isDirectory: true) }
        let resolve = "Library/Application Support/Blackmagic Design/DaVinci Resolve/LUT"
        return [
            .init(id: "std-ofx-system", displayName: "OFX (system)", url: sys("/Library/OFX/Plugins"), kinds: [.ofx], origin: .standard),
            .init(id: "std-vst3-system", displayName: "VST3 (system)", url: sys("/Library/Audio/Plug-Ins/VST3"), kinds: [.vst3], origin: .standard),
            .init(id: "std-vst3-user", displayName: "VST3 (user)", url: usr("Library/Audio/Plug-Ins/VST3"), kinds: [.vst3], origin: .standard),
            .init(id: "std-au-system", displayName: "Audio Units (system)", url: sys("/Library/Audio/Plug-Ins/Components"), kinds: [.audioUnit], origin: .standard),
            .init(id: "std-au-user", displayName: "Audio Units (user)", url: usr("Library/Audio/Plug-Ins/Components"), kinds: [.audioUnit], origin: .standard),
            .init(id: "std-vst-system", displayName: "VST (system)", url: sys("/Library/Audio/Plug-Ins/VST"), kinds: [.vst], origin: .standard),
            .init(id: "std-vst-user", displayName: "VST (user)", url: usr("Library/Audio/Plug-Ins/VST"), kinds: [.vst], origin: .standard),
            // DaVinci Resolve keeps LUTs in LUT/ and DCTLs in LUT/DCTL/ (system and per-user); one root covers both.
            .init(id: "resolve-lut-system", displayName: "Resolve LUT/DCTL (system)", url: sys("/" + resolve), kinds: [.lut, .dctl], origin: .resolve),
            .init(id: "resolve-lut-user", displayName: "Resolve LUT/DCTL (user)", url: usr(resolve), kinds: [.lut, .dctl], origin: .resolve),
        ]
    }
}

/// Removes overlapping roots so nothing is scanned (or counted) twice.
public enum RootDeduplicator {
    public struct Merge: Sendable, Equatable { public var dropped: String; public var into: String; public var reason: String }

    /// - identical canonical roots → merged (kinds unioned into the first);
    /// - root nested inside another → its kinds already covered by the outer root are removed; dropped when nothing remains.
    public static func reduce(_ input: [SourceDescriptor]) -> (kept: [SourceDescriptor], merges: [Merge]) {
        var merges: [Merge] = []
        var list: [SourceDescriptor] = []
        // 1. identical roots
        var byPath: [String: Int] = [:]
        for s in input {
            let c = s.canonicalPath
            if let i = byPath[c] {
                list[i].kinds.formUnion(s.kinds)
                merges.append(.init(dropped: s.id, into: list[i].id, reason: "same folder"))
            } else { byPath[c] = list.count; list.append(s) }
        }
        // 2. nesting (separate disabled stores are never merged into active sources)
        var out: [SourceDescriptor] = []
        for s in list {
            var s = s
            let c = s.canonicalPath
            for outer in list where outer.id != s.id && (outer.disabledOf == nil) == (s.disabledOf == nil) {
                let oc = outer.canonicalPath
                if c.hasPrefix(oc + "/") {
                    let covered = s.kinds.intersection(outer.kinds)
                    if !covered.isEmpty {
                        s.kinds.subtract(covered)
                        merges.append(.init(dropped: s.id, into: outer.id, reason: "inside \(outer.displayName) for \(covered.map(\.title).sorted().joined(separator: "/"))"))
                    }
                }
            }
            if !s.kinds.isEmpty { out.append(s) }
        }
        return (out, merges)
    }
}
