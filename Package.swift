// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "GDCEffectsLibrary",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EffectsLibraryCore", targets: ["EffectsLibraryCore"]),
        .library(name: "EffectsLibraryEngine", targets: ["EffectsLibraryEngine"]),
        .executable(name: "GDCEffectsLibrary", targets: ["EffectsLibrary"]),
    ],
    targets: [
        // Pure models, stable identity, query engine, mock data. No UI, no filesystem.
        .target(name: "EffectsLibraryCore"),
        // Filesystem-facing engine: persistence, diagnostics, read-only scanning, previews/cache, recoverable management.
        .target(name: "EffectsLibraryEngine", dependencies: ["EffectsLibraryCore"]),
        // Synthetic fixtures for tests and benchmarks only (never linked into the app).
        .target(name: "EffectsLibraryTestSupport", dependencies: ["EffectsLibraryCore", "EffectsLibraryEngine"]),
        // SwiftUI application. Build outputs go to external storage (scripts/dev-env.sh).
        .executableTarget(name: "EffectsLibrary", dependencies: ["EffectsLibraryCore", "EffectsLibraryEngine"]),
        // Development benchmark runner (synthetic inventories; no pass/fail thresholds).
        .executableTarget(name: "gel-bench", dependencies: ["EffectsLibraryCore", "EffectsLibraryEngine", "EffectsLibraryTestSupport"]),
        .testTarget(name: "EffectsLibraryCoreTests", dependencies: ["EffectsLibraryCore"]),
        .testTarget(name: "EffectsLibraryEngineTests", dependencies: ["EffectsLibraryCore", "EffectsLibraryEngine", "EffectsLibraryTestSupport"]),
    ]
)
