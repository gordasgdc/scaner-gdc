// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Foundation

/// Deterministic mock inventory for Etapa 1. Fixed dates, no randomness, no real user paths.
/// Covers: long names, missing metadata, duplicates across sources, unavailable/unscanned sources.
public enum MockData {
    public static let sources: [LibrarySource] = [
        .init(id: "ofx-system", displayName: "OFX (system)", path: "/Library/OFX/Plugins", kinds: [.ofx], availability: .available),
        .init(id: "vst3-system", displayName: "VST3 (system)", path: "/Library/Audio/Plug-Ins/VST3", kinds: [.vst3], availability: .available),
        .init(id: "vst3-user", displayName: "VST3 (user)", path: "/Users/mock/Library/Audio/Plug-Ins/VST3", kinds: [.vst3], availability: .available),
        .init(id: "au-system", displayName: "Audio Units (system)", path: "/Library/Audio/Plug-Ins/Components", kinds: [.audioUnit], availability: .available),
        .init(id: "vst-system", displayName: "VST (system)", path: "/Library/Audio/Plug-Ins/VST", kinds: [.vst],
              availability: .unavailable(reason: "Mock: folder not readable (permission denied)")),
        .init(id: "resolve-lut", displayName: "Resolve LUTs", path: "/Library/Application Support/Blackmagic Design/DaVinci Resolve/LUT", kinds: [.lut], availability: .available),
        .init(id: "resolve-dctl", displayName: "Resolve DCTL", path: "/Library/Application Support/Blackmagic Design/DaVinci Resolve/LUT/DCTL", kinds: [.dctl], availability: .available),
        .init(id: "custom-1", displayName: "Custom: Project Looks", path: "/Volumes/Mock/Looks", kinds: [.lut, .dctl], availability: .notScanned),
    ]

    private static let epoch = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01T00:00:00Z
    private static func day(_ n: Int) -> Date { epoch.addingTimeInterval(Double(n) * 86_400) }

    public static let items: [EffectItem] = {
        var out: [EffectItem] = []
        func add(_ name: String, _ kind: ItemKind, _ src: String, _ dir: String, _ file: String,
                 vendor: String? = nil, version: String? = nil, bid: String? = nil,
                 d: Int? = nil, size: Int64? = nil, fx: [String] = [], arch: [String]? = nil) {
            out.append(EffectItem(name: name, kind: kind, sourceID: src, path: "\(dir)/\(file)",
                                   vendor: vendor, version: version, bundleIdentifier: bid,
                                   modified: d.map(day), sizeBytes: size, exposedEffects: fx, architectures: arch))
        }
        let ofx = "/Library/OFX/Plugins"
        add("Halation Pro", .ofx, "ofx-system", ofx, "HalationPro.ofx.bundle", vendor: "Northlight", version: "2.4.1", bid: "com.northlight.halation", d: 310, size: 18_400_000, fx: ["Halation", "Halation Mask"], arch: ["arm64", "x86_64"])
        add("Film Grain Studio", .ofx, "ofx-system", ofx, "FilmGrainStudio.ofx.bundle", vendor: "Northlight", version: "1.9.0", bid: "com.northlight.grain", d: 288, size: 9_200_000, fx: ["Grain 35mm", "Grain 16mm", "Grain Overlay"], arch: ["arm64"])
        add("Optical Diffusion", .ofx, "ofx-system", ofx, "OpticalDiffusion.ofx.bundle", vendor: "GDC", version: "1.2.0", bid: "dev.gordas.opticaldiffusion", d: 330, size: 4_100_000, fx: ["Diffusion"], arch: ["arm64"])
        add("Lens Flare & Bokeh Designer Ultimate Edition with Extended Anamorphic Streak Library", .ofx, "ofx-system", ofx, "LensFlareBokehDesignerUltimate.ofx.bundle", vendor: "Prismatic Labs International", version: "5.0.0-beta.12", bid: "com.prismatic.flare.ultimate", d: 12, size: 212_000_000, fx: ["Flare", "Bokeh", "Streak", "Veiling Glare"], arch: ["x86_64"])
        add("MysteryFX", .ofx, "ofx-system", ofx, "mfx.ofx.bundle", d: 100)
        add("Noise Reducer", .ofx, "ofx-system", ofx, "NoiseReducer.ofx.bundle", vendor: "Quietframe", version: "3.1", d: 200, size: 52_000_000, fx: ["Spatial NR", "Temporal NR"], arch: ["arm64", "x86_64"])
        add("Color Warper Extras", .ofx, "ofx-system", ofx, "ColorWarperExtras.ofx.bundle", vendor: "Hueworks", version: "0.9.3", bid: "io.hueworks.warper", d: 250, size: 7_700_000, fx: ["Warper"], arch: ["arm64"])
        add("Sharpen Detail", .ofx, "ofx-system", ofx, "SharpenDetail.ofx.bundle", vendor: "Quietframe", version: "1.0.0", d: 140, size: 3_300_000, fx: ["Sharpen"], arch: ["arm64"])

        let lut = "/Library/Application Support/Blackmagic Design/DaVinci Resolve/LUT"
        let lutNames: [(String, String?, Int?)] = [
            ("Kodak 2383 D55", "Print Emulation", 20), ("Kodak 2383 D65", "Print Emulation", 21), ("Fuji 3513 D60", "Print Emulation", 22),
            ("Rec709 to Log Warm", "Conversion", 80), ("LogC to Rec709 v2", "Conversion", 81), ("S-Log3 to Rec709 Neutral", "Conversion", 82),
            ("Teal Orange Soft", "Creative", 190), ("Bleach Bypass Light", "Creative", 191), ("Cross Process Cold", "Creative", 192),
            ("Night Exterior Moonlight Cool with Lifted Shadows and Reduced Contrast Variant B", "Creative", 40), ("untitled", nil, nil),
        ]
        for (n, v, d) in lutNames {
            add(n, .lut, "resolve-lut", lut, "\(n).cube", vendor: v == nil ? nil : "GDC", version: nil, d: d, size: 1_000_000 + Int64(n.count) * 1_000, fx: [])
        }
        let dctl = lut + "/DCTL"
        for (n, d) in [("Soft Clip Highlights", 60), ("Gamut Compress", 61), ("Vignette Radial", 62), ("Channel Mixer Lite", 63), ("Highlight Desaturate", nil)] as [(String, Int?)] {
            add(n, .dctl, "resolve-dctl", dctl, "\(n).dctl", vendor: d == nil ? nil : "GDC", d: d, size: 4_000 + Int64(n.count) * 100)
        }

        // VST3: some duplicated between system and user locations.
        let v3s = "/Library/Audio/Plug-Ins/VST3", v3u = "/Users/mock/Library/Audio/Plug-Ins/VST3"
        add("Reverb Chamber", .vst3, "vst3-system", v3s, "ReverbChamber.vst3", vendor: "Echoform", version: "2.0.1", bid: "com.echoform.reverb", d: 150, size: 14_000_000, arch: ["arm64", "x86_64"])
        add("Reverb Chamber", .vst3, "vst3-user", v3u, "ReverbChamber.vst3", vendor: "Echoform", version: "1.8.0", bid: "com.echoform.reverb", d: 90, size: 13_000_000, arch: ["arm64", "x86_64"])
        add("Parametric EQ 8", .vst3, "vst3-system", v3s, "ParametricEQ8.vst3", vendor: "Equalis", version: "4.2.0", bid: "com.equalis.peq8", d: 270, size: 6_000_000, arch: ["arm64"])
        add("Compressor Vintage Opto", .vst3, "vst3-user", v3u, "CompressorVintageOpto.vst3", vendor: "Equalis", version: "1.1.5", bid: "com.equalis.opto", d: 300, size: 8_000_000, arch: ["arm64"])
        add("Synth ???", .vst3, "vst3-user", v3u, "SynthUnknown.vst3", d: 5)
        add("Tape Saturator", .vst3, "vst3-system", v3s, "TapeSaturator.vst3", vendor: "Echoform", version: "1.0.0", bid: "com.echoform.tape", d: 340, size: 5_100_000, arch: ["x86_64"])

        let au = "/Library/Audio/Plug-Ins/Components"
        add("Reverb Chamber", .audioUnit, "au-system", au, "ReverbChamber.component", vendor: "Echoform", version: "2.0.1", bid: "com.echoform.reverb.au", d: 150, size: 14_000_000, arch: ["arm64", "x86_64"])
        add("Parametric EQ 8", .audioUnit, "au-system", au, "ParametricEQ8.component", vendor: "Equalis", version: "4.2.0", bid: "com.equalis.peq8.au", d: 270, size: 6_100_000, arch: ["arm64"])
        add("Delay Ping Pong", .audioUnit, "au-system", au, "DelayPingPong.component", vendor: "Echoform", version: "1.3.2", bid: "com.echoform.delay.au", d: 210, size: 2_900_000, arch: ["arm64"])
        add("Vocal Rider", .audioUnit, "au-system", au, "VocalRider.component", vendor: "Levelwise", d: 120)

        // Legacy VST: its source is unavailable in the mock, so the items are kept as last known state.
        let v2 = "/Library/Audio/Plug-Ins/VST"
        add("Old Chorus", .vst, "vst-system", v2, "OldChorus.vst", vendor: "Retroworks", version: "1.0", d: 20, size: 800_000, arch: ["x86_64"])
        add("Legacy Gate", .vst, "vst-system", v2, "LegacyGate.vst", d: 30, size: 600_000)

        // Custom source never scanned: one pre-known item with missing metadata.
        add("Project Look 04", .lut, "custom-1", "/Volumes/Mock/Looks", "Project Look 04.cube", d: 8, size: 1_200_000)
        return out
    }()
}
