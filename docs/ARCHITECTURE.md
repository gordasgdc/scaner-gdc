# Scaner GDC — Architecture

Native macOS app that inventories, shows and (later, recoverably) manages installed plugins and resources:
OFX, LUT, DCTL, VST3, Audio Units, VST. It is **not** GDC Plugin Manager (the developer platform/catalog);
it is a separate product prepared for integration into it.

## Baseline
- Swift 6 language mode, SwiftUI (AppKit only where justified), SwiftPM package. **Minimum macOS 14** (`.inspector`, `@Observable`).
- Tested toolchain: Xcode 27.2 / Swift 6.4 on macOS 27. Universal build is a release-time decision (Etapa 5).

## Modules
| Target | Responsibility | Must not |
|---|---|---|
| `EffectsLibraryCore` | models, stable identity, `LibraryQuery` (filter/sort), `SelectionNavigation`, mock data | UI, filesystem, image work |
| `EffectsLibrary` (app) | SwiftUI views, `AppState` (presentation state), `Theme` (semantic colors/metrics/type scale) | parse files, touch the filesystem |
| Planned (Etapa 2+) | `Scanning`, `Previews/Cache`, `FileOps/Journal`, `Diagnostics` | run on the UI thread; execute plugin binaries or DCTL |

## Identity (`StableID`)
- `id` = SHA-256 prefix of `kind | bundleIdentifier-or-"-" | standardized path`. Same file → same id across rescans.
- **Duplicate** = same `duplicateKey` (`kind | bundle id or name`, lowercased) in more than one location. Duplicates keep distinct ids.
- **Move** changes the path, so the id changes; the Disabled/Restore journal (Etapa 4) must record old id → new id explicitly.
- **Restore** returns the item to its original recorded path, never overwriting an existing item.
- Vendor, version, compatibility, architectures may be unknown (`nil`); nothing is invented. "Present on disk" never means
  loaded, compatible or licensed in a host.

## Source model
A `LibrarySource` has availability `available | unavailable(reason) | notScanned`. An unreadable source is never shown as an empty success.
Items of an unavailable source are shown as last known state, flagged.

## Product boundaries (binding for later stages)
- Scan: only the known locations, per-user directory resolved dynamically, custom sources via native picker, Resolve LUT/DCTL locations
  discovered narrowly. No whole-disk scan, no broad permissions without demonstrated need.
- Read metadata/resources without loading or executing plugin binaries; never execute DCTL.
- LUT preview: declared supported variants only (see Etapa 3 spec); no universal `.3dl` promise; reference image color space and rights documented.
- DCTL: metadata + fallback only; a real render needs a separate authorized integration. A generic image is never presented as the DCTL result.
- Management: Disabled folder is an app folder, **not** `com.apple.quarantine`. No changes to signatures, licenses, security attributes or bundle internals.
  Preflight, in-app confirmation, persistent journal, collision detection, identity check, crash recovery, no-overwrite restore;
  same-volume vs cross-volume handled separately. No privileged helper in v1; unwritable locations show the reason and block.

## Etapa 1 UI (this candidate)
Sidebar (library / types / sources) · adaptive grid (column count computed, keyboard arrows move selection) · hideable inspector ·
toolbar search/filter(vendor)/sort · native menu "Library" · context menu · Settings (System/Dark/Light, 4 text sizes, previews).
Unimplemented actions (Rescan, Reveal in Finder, Regenerate Preview, Move/Restore, custom source) are visibly disabled — never simulated.
Implemented: Copy Path, Show Previews (placeholder area "No preview"), Show Inspector.

## Design tokens
All colors/dimensions live in `Theme.swift` (neutral grays, one warm-copper accent, hairline separators = 1 physical pixel).
`scripts/preflight.sh` fails on literal colors elsewhere. Text scale via `\.textScale` (`.typo(...)`).

## Dev environment vs product
`scripts/dev-env.sh` (storage gate + external build/cache/temp paths) is development-only. The shipped app contains no machine-specific paths.

## Update 0.2.0
- Engine modules: Scanning (read-only, `InventoryAssembler` adds the Disabled stores), Previews (cube parser/renderer, cache, service), Management (`ManagementEngine`: preflight plan → in-app confirmation → same-volume `renamex_np(RENAME_EXCL)` or cross-volume copy → manifest verify → exclusive rename → Trash; fsync'd JSONL journal; recovery of interrupted operations), Diagnostics (rotating JSON log, redaction, local zip export), Persistence.
- Disabled store: sibling folder `<root> (Disabled by GDC)` (hosts do not scan it) or a user-chosen folder; a `.gdc-restore` note beside it duplicates the journal record.
- Limits: no privileged helper, so roots such as `/Library/...` are reported as not writable. Hosts are never closed; a running host only produces a warning.
- Product details (0.4.0; optional own-key discovery 0.5.0): `EffectsLibraryCore/ProductRecord.swift` (records keyed by `ProductKey`, path-independent) and `EffectsLibraryEngine/Enrichment/` — `URLPolicy` + `URLSessionFetcher` (https only, public hosts, re-validated redirects, size/time caps), `ImageSanitizer` (sniff, bounds, downscale, re-encode), `PageMetadataExtractor` (text as data), `ProductMatcher` (conservative matching; ambiguity = proposal), `EnrichmentStore` (metadata in Application Support, user images separate from the re-fetchable cover cache, atomic JSON with schema version), `EnrichmentService` (lookup, associate page, accept image, batch). Discovery is a `SearchProvider` adapter; the shipped provider is `NoSearchProvider` (no service/credentials exist). Real network checks: `gel-bench net-probe <url>` (outside the deterministic tests). See `docs/PRIVACY.md`.
- Icon: `scripts/make-icon.sh` renders the logo master SVG (path from `GEL_ICON_MASTER`) with AppKit into an `.icns`; the Dock/Finder variant sits on a graphite plate, the master is never modified.
- Verification tools: `scripts/test-crossvolume.sh` (real APFS image), `scripts/shots.sh` (window screenshots on a synthetic library), `gel-bench` (synthetic benchmarks, no thresholds).
