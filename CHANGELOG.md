# Changelog

## 0.5.1
- Licence: GNU GPL v3 only with additional terms (§7); credit line in About; name/logo regime (`branding/`); neutral icon for derived builds; third-party notices.
- Automatic search results are now **transient** (memory only, never saved): Brave's standard plan does not allow storing results. A found page is opened in the browser and associated manually. Settings explain that the Brave Search API is a separate, optional, experimental service.
- Batch summary reports pages found by search separately from confirmed proposals.

## 0.5.0 — not published
- **Honest lookup results.** Distinct outcomes and counters: *not searched (automatic search not set up)*, *not found after searching*, *ambiguous*, *network problem*, *updated from a page you associated*. A batch with no search service no longer reports “not found”.
- **Optional automatic discovery with your own key**: Brave Search API (bring your own key; stored in the Keychain; off until set; no key in the app). Candidates are always proposals you confirm. Verified with recorded response shapes only; not yet with a live key.
- Real-network probe tool (`gel-bench net-probe`) for HTTPS pages, images, redirects, timeouts and cancel.

## 0.4.0 — candidate (unpublished)
- **Search Cover and Details**: optional product cover, short description, producer and official-page link for items without an image; from your own image or an official page you associate. Real previews, package icons, online covers and your own images are labelled separately.
- **Fill Items Without Cover…** for a selection or the library, with progress, cancel and a summary (completed, to confirm, not found, errors).
- Online lookup is off by default; the first use explains what is sent. Never sent: paths, files, licences, your name, your inventory. Addresses must be https and public; redirects, size, time and image type/dimensions are limited. Third-party images stay on your Mac.
- Associations survive rescans and moves; clearing the cache keeps them and your own images. Your choices are never overwritten.
- No product-page search service is included in 0.4.0 (0.5.0 adds an optional own-key one).

## 0.3.0 — candidate (unpublished)
- New name **Scaner GDC** and icon (Dock, Finder, About); About shows the author credit.
- Universal build (Apple silicon + Intel), signed with Developer ID, notarized and stapled; distributed as a disk image.
- Diagnostics export anonymizes paths with spaces and `~/` paths, drops free-text reasons and item names unless you opt in to paths, and keeps secret redaction in every mode.
- Inspector and sort controls are labelled for VoiceOver and keyboard use.
- Site (EN/RO/ES) and repository documentation prepared; the download is not available until the release is published.

## 0.2.0 — local candidate (unpublished)
- Renamed to **Scaner GDC** with the approved magnifier icon (Dock/About).
- Real read-only scanning of OFX, LUT, DCTL, VST3, Audio Unit and VST folders plus your own folders; progress, cancel, last-known inventory when a folder cannot be read.
- Previews: bundle icons and `.cube` LUT renders on a synthetic reference image (before/after); DCTL is never run. Local cache with size limit.
- Move to Disabled / Restore with a check first, confirmation, activity log and recovery after an interruption; nothing is overwritten or deleted.
- Reveal in Finder, Copy Path, diagnostics export (local, never uploaded), verbose logging on request.

## 0.1.0 — local candidate (unpublished)
- First interface on mock data: sidebar, adaptive grid, inspector, search/filter/sort, menus, settings (appearance, text size).
- Real scanning and file operations are not available yet.
