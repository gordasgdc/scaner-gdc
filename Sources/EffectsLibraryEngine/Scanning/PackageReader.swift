// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Foundation
import EffectsLibraryCore

public struct ScanLimits: Sendable {
    public var maxDepthBundles = 4
    public var maxDepthFiles = 10
    public var maxItemsPerSource = 50_000
    public var maxEntriesForBundleSize = 5_000
    public var maxMetadataBytes = 1_048_576
    public var maxConcurrentSources = 4
    public init() {}
}

/// Turns one filesystem entry into an `EffectItem` by reading metadata files only (no code is loaded or run).
struct PackageReader {
    let limits: ScanLimits
    let fm = FileManager.default

    static let lutExtensions: Set<String> = ["cube", "3dl", "dat", "vlt", "mga", "csp"]

    static func kind(forBundleName name: String) -> ItemKind? {
        let l = name.lowercased()
        if l.hasSuffix(".ofx.bundle") { return .ofx }
        if l.hasSuffix(".vst3") { return .vst3 }
        if l.hasSuffix(".component") { return .audioUnit }
        if l.hasSuffix(".vst") { return .vst }
        return nil
    }

    func readBundle(_ url: URL, kind: ItemKind, source: SourceDescriptor) -> EffectItem {
        let fileName = url.lastPathComponent
        var stem = fileName
        for suf in [".ofx.bundle", ".vst3", ".component", ".vst"] where stem.lowercased().hasSuffix(suf) { stem = String(stem.dropLast(suf.count)); break }

        let plist = readPlist(url.appendingPathComponent("Contents/Info.plist"))
        var name = (plist?["CFBundleDisplayName"] as? String) ?? (plist?["CFBundleName"] as? String) ?? stem
        if name.trimmingCharacters(in: .whitespaces).isEmpty { name = stem }
        var version = (plist?["CFBundleShortVersionString"] as? String) ?? (plist?["CFBundleVersion"] as? String)
        var vendor: String? = nil
        var effects: [String] = []
        var details: [String: String] = [:]

        if kind == .vst3, let info = readJSON(url.appendingPathComponent("Contents/Resources/moduleinfo.json")) {
            if let f = info["Factory Info"] as? [String: Any], let v = f["Vendor"] as? String, !v.isEmpty { vendor = v }
            if version == nil, let v = info["Version"] as? String { version = v }
            if let classes = info["Classes"] as? [[String: Any]] {
                effects = classes.filter { ($0["Category"] as? String) == "Audio Module Class" }.compactMap { $0["Name"] as? String }
            }
        }
        if kind == .audioUnit, let comps = plist?["AudioComponents"] as? [[String: Any]] {
            for c in comps {
                guard let n = c["name"] as? String else { continue }
                if let r = n.range(of: ": ") {
                    if vendor == nil { vendor = String(n[..<r.lowerBound]) }
                    effects.append(String(n[r.upperBound...]))
                } else { effects.append(n) }
            }
        }
        if let min = plist?["LSMinimumSystemVersion"] as? String { details["Minimum macOS"] = min }

        let exeName = (plist?["CFBundleExecutable"] as? String) ?? firstExecutableName(in: url.appendingPathComponent("Contents/MacOS"))
        let arch = exeName.flatMap { MachOReader.architectures(at: url.appendingPathComponent("Contents/MacOS/\($0)")) }

        var support = PreviewSupport.none
        var note: String? = "No icon resource found in the bundle."
        if iconURL(bundle: url, plist: plist) != nil { support = .bundleIcon; note = "Bundle icon (not a render of the effect)." }

        let rv = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isSymbolicLinkKey])
        if rv?.isSymbolicLink == true { details["Symbolic link"] = (try? fm.destinationOfSymbolicLink(atPath: url.path)) ?? "yes" }

        return EffectItem(name: name, kind: kind, sourceID: source.id, path: url.path, vendor: vendor, version: version,
                          bundleIdentifier: plist?["CFBundleIdentifier"] as? String, modified: rv?.contentModificationDate,
                          sizeBytes: treeSize(url), exposedEffects: effects, architectures: arch,
                          state: source.disabledOf == nil ? .active : .disabled, details: details,
                          previewSupport: support, previewNote: note)
    }

    func readFile(_ url: URL, kind: ItemKind, source: SourceDescriptor) -> EffectItem {
        let ext = url.pathExtension.lowercased()
        let stem = url.deletingPathExtension().lastPathComponent
        let rv = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        var details: [String: String] = ["Format": ext.uppercased()]
        var support = PreviewSupport.none
        var note: String?
        if kind == .lut {
            if ext == "cube" {
                if let h = LUTHeaderReader.readCubeHeader(at: url) {
                    if let s = h.size3D { details["Size"] = "3D \(s)³" }
                    if let s = h.size1D { details["Size"] = "1D \(s)" }
                    if let t = h.title, !t.isEmpty { details["Title"] = t }
                    if let a = h.domainMin, let b = h.domainMax { details["Domain"] = "\(a.map { String($0) }.joined(separator: " ")) → \(b.map { String($0) }.joined(separator: " "))" }
                }
                support = .lutCube; note = "Rendered from the parsed LUT on a synthetic reference image."
            } else { note = "Preview is supported for .cube LUTs only (\(ext.uppercased()) is listed, not rendered)." }
        } else {
            if let f = DCTLReader.read(at: url) {
                details["UI parameters"] = String(f.uiParameterCount)
                details["Transform function"] = f.hasTransformFunction ? "found" : "not found"
                details["Lines"] = String(f.lineCount) + (f.truncated ? "+" : "")
            }
            note = "DCTL is shown from metadata only; it is never compiled or executed here."
        }
        return EffectItem(name: stem, kind: kind, sourceID: source.id, path: url.path, modified: rv?.contentModificationDate,
                          sizeBytes: rv?.fileSize.map(Int64.init), state: source.disabledOf == nil ? .active : .disabled,
                          details: details, previewSupport: support, previewNote: note)
    }

    // MARK: helpers

    func iconURL(bundle: URL, plist: [String: Any]?) -> URL? {
        guard var icon = plist?["CFBundleIconFile"] as? String, !icon.isEmpty else { return nil }
        if (icon as NSString).pathExtension.isEmpty { icon += ".icns" }
        let u = bundle.appendingPathComponent("Contents/Resources/\(icon)")
        return fm.fileExists(atPath: u.path) ? u : nil
    }

    func readPlist(_ url: URL) -> [String: Any]? {
        guard let d = boundedData(url), let o = try? PropertyListSerialization.propertyList(from: d, options: [], format: nil) else { return nil }
        return o as? [String: Any]
    }
    func readJSON(_ url: URL) -> [String: Any]? {
        guard let d = boundedData(url), let o = try? JSONSerialization.jsonObject(with: d) else { return nil }
        return o as? [String: Any]
    }
    func boundedData(_ url: URL) -> Data? {
        guard let a = try? fm.attributesOfItem(atPath: url.path), let n = a[.size] as? Int, n <= limits.maxMetadataBytes else { return nil }
        return try? Data(contentsOf: url)
    }
    func firstExecutableName(in dir: URL) -> String? {
        (try? fm.contentsOfDirectory(atPath: dir.path))?.sorted().first { !$0.hasPrefix(".") }
    }
    /// Sum of file sizes, or nil (unknown) when the bundle has more entries than the cap.
    func treeSize(_ url: URL) -> Int64? {
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [], errorHandler: { _, _ in true }) else { return nil }
        var total: Int64 = 0, n = 0
        for case let f as URL in e {
            n += 1; if n > limits.maxEntriesForBundleSize { return nil }
            let v = try? f.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if v?.isRegularFile == true { total += Int64(v?.fileSize ?? 0) }
        }
        return total
    }
}
