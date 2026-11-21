#!/bin/bash
# Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
# Regenerates the site from the FINAL verified package: size, SHA-256 and architectures are read from the DMG itself.
# Without --published the page stays in preview state (no active download). Use --published only after the real release asset is verified online.
# Usage: scripts/site-from-candidate.sh <attempt-dir> [--published]
set -euo pipefail
cd "$(dirname "$0")/.."
A="${1:?attempt directory}"; shift || true
V="$(cat VERSION)"; DMG="$A/ScanerGDC-macOS-$V.dmg"
[ -f "$DMG" ] || { echo "missing $DMG" >&2; exit 1; }
( cd "$A" && shasum -a 256 -c "$(basename "$DMG").sha256" >/dev/null ) || { echo "checksum mismatch" >&2; exit 1; }
SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"
BYTES="$(stat -f %z "$DMG")"; SIZE="$(python3 -c "print(f'{$BYTES/1e6:.1f} MB')")"
MNT="$(hdiutil attach "$DMG" -nobrowse -readonly | awk -F'\t' '/\/Volumes\//{print $NF}' | head -1)"
trap 'hdiutil detach "$MNT" -quiet 2>/dev/null || true' EXIT
ARCHS="$(lipo -archs "$MNT/Scaner GDC.app/Contents/MacOS/GDCEffectsLibrary")"
python3 scripts/build-site.py --version "$V" --dmg-size "$SIZE" --sha256 "$SHA" --archs "$ARCHS" --dmg-bytes "$BYTES" "$@"
python3 scripts/verify-site.py
