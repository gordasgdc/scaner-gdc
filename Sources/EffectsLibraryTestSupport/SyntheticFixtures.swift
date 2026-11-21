// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Foundation
import EffectsLibraryCore
import EffectsLibraryEngine
import CoreGraphics
import ImageIO

/// Synthetic plugin/LUT/DCTL trees for tests and benchmarks. Everything is generated; nothing is copied from a real install.
public enum SyntheticFixtures {
    /// Test/benchmark output must live on external storage. `scripts/dev-env.sh` sets `TMPDIR` there and exports `GEL_OUT`.
    public static func workRoot(_ name: String = UUID().uuidString) throws -> URL {
        guard let out = ProcessInfo.processInfo.environment["GEL_OUT"], !out.isEmpty else {
            throw FixtureError.storageGateMissing
        }
        let u = URL(fileURLWithPath: out, isDirectory: true).appendingPathComponent("temp/fixtures/\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    public enum FixtureError: Error { case storageGateMissing }

    // MARK: Mach-O

    /// A minimal Mach-O header (not runnable): thin if one arch, fat otherwise.
    public static func machO(_ archs: [String]) -> Data {
        func cpu(_ a: String) -> (UInt32, UInt32) {
            switch a { case "arm64": (0x0100000C, 0); case "arm64e": (0x0100000C, 2); case "x86_64": (0x01000007, 3); default: (7, 3) }
        }
        var d = Data()
        func be(_ v: UInt32) { for s in [24, 16, 8, 0] { d.append(UInt8((v >> UInt32(s)) & 0xFF)) } }
        func le(_ v: UInt32) { for s in [0, 8, 16, 24] { d.append(UInt8((v >> UInt32(s)) & 0xFF)) } }
        if archs.count == 1 {
            le(0xFEEDFACF); le(cpu(archs[0]).0); le(cpu(archs[0]).1); le(6); le(0); le(0); le(0); le(0)
        } else {
            be(0xCAFEBABE); be(UInt32(archs.count))
            for a in archs { be(cpu(a).0); be(cpu(a).1); be(0x4000); be(0x100); be(14) }
        }
        d.append(Data(count: 64))
        return d
    }

    // MARK: Bundles

    @discardableResult
    public static func bundle(_ kind: ItemKind, name: String, in dir: URL, bundleID: String? = nil, version: String? = "1.0.0",
                              vendor: String? = nil, archs: [String] = ["arm64"], withIcon: Bool = false,
                              effects: [String] = [], extraBytes: Int = 0) throws -> URL {
        let ext: String = switch kind { case .ofx: "ofx.bundle"; case .vst3: "vst3"; case .audioUnit: "component"; case .vst: "vst"; default: "bundle" }
        let b = dir.appendingPathComponent("\(name).\(ext)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: b.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        try fm.createDirectory(at: b.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
        var plist: [String: Any] = ["CFBundleName": name, "CFBundleExecutable": name, "CFBundlePackageType": "BNDL"]
        if let bundleID { plist["CFBundleIdentifier"] = bundleID }
        if let version { plist["CFBundleShortVersionString"] = version }
        if withIcon { plist["CFBundleIconFile"] = "icon" }
        if kind == .audioUnit, let vendor {
            plist["AudioComponents"] = (effects.isEmpty ? [name] : effects).map { ["name": "\(vendor): \($0)", "type": "aufx"] }
        }
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: b.appendingPathComponent("Contents/Info.plist"))
        var exe = machO(archs); if extraBytes > 0 { exe.append(Data(count: extraBytes)) }
        try exe.write(to: b.appendingPathComponent("Contents/MacOS/\(name)"))
        if kind == .vst3 {
            var info: [String: Any] = ["Name": name, "Version": version ?? "0"]
            if let vendor { info["Factory Info"] = ["Vendor": vendor] }
            info["Classes"] = (effects.isEmpty ? [name] : effects).map { ["Name": $0, "Category": "Audio Module Class"] }
            try JSONSerialization.data(withJSONObject: info).write(to: b.appendingPathComponent("Contents/Resources/moduleinfo.json"))
        }
        if withIcon { try tinyICNS().write(to: b.appendingPathComponent("Contents/Resources/icon.icns")) }
        return b
    }

    /// A valid 16×16 `.icns` (ic04-less: uses 'icp4' PNG payload).
    public static func tinyICNS() -> Data {
        let png = solidPNG(width: 16, height: 16, rgb: (200, 120, 60))
        var d = Data("icns".utf8)
        func be32(_ v: Int) -> Data { Data([UInt8((v >> 24) & 255), UInt8((v >> 16) & 255), UInt8((v >> 8) & 255), UInt8(v & 255)]) }
        d.append(be32(8 + 8 + png.count)); d.append(Data("icp4".utf8)); d.append(be32(8 + png.count)); d.append(png)
        return d
    }

    public static func solidPNG(width: Int, height: Int, rgb: (UInt8, UInt8, UInt8)) -> Data {
        var px = [UInt8](); for _ in 0..<(width * height) { px += [rgb.0, rgb.1, rgb.2, 255] }
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: &px, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let img = ctx.makeImage()!
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, img, nil); CGImageDestinationFinalize(dest)
        return out as Data
    }

    // MARK: LUT / DCTL

    /// Valid 3D .cube (red varies fastest). `f` maps input (0–1) to output.
    public static func cube3D(size: Int, title: String? = "Synthetic", domain: (Double, Double) = (0, 1),
                              _ f: (Double, Double, Double) -> (Double, Double, Double) = { ($0, $1, $2) }) -> String {
        var s = ""; if let title { s += "TITLE \"\(title)\"\n" }
        s += "# synthetic\nLUT_3D_SIZE \(size)\n"
        if domain != (0, 1) { s += "DOMAIN_MIN \(domain.0) \(domain.0) \(domain.0)\nDOMAIN_MAX \(domain.1) \(domain.1) \(domain.1)\n" }
        let n = Double(size - 1)
        for b in 0..<size { for g in 0..<size { for r in 0..<size {
            let i = (domain.0 + Double(r) / n * (domain.1 - domain.0), domain.0 + Double(g) / n * (domain.1 - domain.0), domain.0 + Double(b) / n * (domain.1 - domain.0))
            let o = f((i.0 - domain.0) / (domain.1 - domain.0), (i.1 - domain.0) / (domain.1 - domain.0), (i.2 - domain.0) / (domain.1 - domain.0))
            s += String(format: "%.6f %.6f %.6f\n", o.0, o.1, o.2)
        } } }
        return s
    }

    public static func cube1D(size: Int, _ f: (Double) -> Double = { $0 }) -> String {
        var s = "TITLE \"Synthetic 1D\"\nLUT_1D_SIZE \(size)\n"
        for i in 0..<size { let v = f(Double(i) / Double(size - 1)); s += String(format: "%.6f %.6f %.6f\n", v, v, v) }
        return s
    }

    public static let dctlSample = """
    // synthetic DCTL
    DEFINE_UI_PARAMS(gain, Gain, DCTLUI_SLIDER_FLOAT, 1.0, 0.0, 2.0, 0.01)
    DEFINE_UI_PARAMS(lift, Lift, DCTLUI_SLIDER_FLOAT, 0.0, -1.0, 1.0, 0.01)
    __DEVICE__ float3 transform(int p_Width, int p_Height, int p_X, int p_Y, float p_R, float p_G, float p_B)
    { return make_float3(p_R * gain + lift, p_G * gain + lift, p_B * gain + lift); }
    """

    // MARK: Whole trees

    public struct Counts: Sendable { public var ofx = 0, vst3 = 0, au = 0, vst = 0, luts = 0, dctls = 0
        public init(ofx: Int = 0, vst3: Int = 0, au: Int = 0, vst: Int = 0, luts: Int = 0, dctls: Int = 0) {
            self.ofx = ofx; self.vst3 = vst3; self.au = au; self.vst = vst; self.luts = luts; self.dctls = dctls } }

    /// Builds `root/{OFX,VST3,Components,VST,LUT/DCTL}` and returns the matching source descriptors (only non-empty kinds).
    public static func populate(root: URL, _ c: Counts, lutSize: Int = 17) throws -> (descriptors: [SourceDescriptor], total: Int) {
        let fm = FileManager.default
        var desc: [SourceDescriptor] = []
        func dir(_ n: String) throws -> URL { let u = root.appendingPathComponent(n, isDirectory: true); try fm.createDirectory(at: u, withIntermediateDirectories: true); return u }
        if c.ofx > 0 { let d = try dir("OFX"); for i in 0..<c.ofx { try bundle(.ofx, name: "OFX Effect \(i)", in: d, bundleID: "com.synthetic.ofx\(i)", version: "1.\(i % 9).0", archs: i % 3 == 0 ? ["arm64", "x86_64"] : ["arm64"]) }
            desc.append(.init(id: "fx-ofx", displayName: "OFX", url: d, kinds: [.ofx], origin: .standard)) }
        if c.vst3 > 0 { let d = try dir("VST3"); for i in 0..<c.vst3 { try bundle(.vst3, name: "V3 Plugin \(i)", in: d, bundleID: "com.synthetic.v3.\(i)", vendor: "Vendor \(i % 5)", effects: ["Plugin \(i)"]) }
            desc.append(.init(id: "fx-vst3", displayName: "VST3", url: d, kinds: [.vst3], origin: .standard)) }
        if c.au > 0 { let d = try dir("Components"); for i in 0..<c.au { try bundle(.audioUnit, name: "AU Plugin \(i)", in: d, bundleID: "com.synthetic.au.\(i)", vendor: "Vendor \(i % 5)", effects: ["Plugin \(i)"]) }
            desc.append(.init(id: "fx-au", displayName: "Audio Units", url: d, kinds: [.audioUnit], origin: .standard)) }
        if c.vst > 0 { let d = try dir("VST"); for i in 0..<c.vst { try bundle(.vst, name: "Old VST \(i)", in: d, bundleID: "com.synthetic.vst.\(i)", version: nil) }
            desc.append(.init(id: "fx-vst", displayName: "VST", url: d, kinds: [.vst], origin: .standard)) }
        if c.luts > 0 || c.dctls > 0 {
            let l = try dir("LUT"); let dd = try dir("LUT/DCTL")
            for i in 0..<c.luts { try cube3D(size: lutSize, title: "Look \(i)") { (min($0 * 1.1, 1), $1, max($2 - 0.05 * Double(i % 4), 0)) }.write(to: l.appendingPathComponent("Look \(i).cube"), atomically: true, encoding: .utf8) }
            for i in 0..<c.dctls { try dctlSample.write(to: dd.appendingPathComponent("Tool \(i).dctl"), atomically: true, encoding: .utf8) }
            desc.append(.init(id: "fx-resolve", displayName: "Resolve LUT/DCTL", url: l, kinds: [.lut, .dctl], origin: .resolve))
        }
        return (desc, c.ofx + c.vst3 + c.au + c.vst + c.luts + c.dctls)
    }
}
