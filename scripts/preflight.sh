#!/bin/bash
# Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
# Local preflight: external-storage gate, tests, release build, bundle sanity. Judges real exit codes.
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/dev-env.sh || exit 3
LOG="$GEL_EVIDENCE/preflight-$(cat VERSION).log"; : > "$LOG"
fail=0
step() { local n="$1"; shift; if "$@" >>"$LOG" 2>&1; then echo "OK   $n"; else echo "FAIL $n (see $LOG)"; fail=1; fi; }
step "swift test" swift test --scratch-path "$GEL_SCRATCH"
step "build-app release" scripts/build-app.sh release
APP="$GEL_BUILD_DIR/GDCEffectsLibrary-$(cat VERSION).app"
step "icon in bundle (icns, plist key)" bash -c "test -s '$APP/Contents/Resources/AppIcon.icns' && plutil -extract CFBundleIconFile raw '$APP/Contents/Info.plist' | grep -qx AppIcon"
step "display name Scaner GDC" bash -c "plutil -extract CFBundleDisplayName raw '$APP/Contents/Info.plist' | grep -qx 'Scaner GDC'"
step "icon master unchanged (sha256)" bash -c "cd '$GEL_OUT/artifacts/icon' && shasum -a 256 -c master.sha256"
step "cross-volume real test" scripts/test-crossvolume.sh
step "benchmark runs" bash -c "$(swift build --scratch-path "$GEL_SCRATCH" --show-bin-path)/gel-bench bench '$GEL_OUT/benchmarks/bench-$(cat VERSION).json'"
step "codesign verify" codesign --verify --strict "$APP"
step "bundle id + min OS" bash -c "plutil -extract CFBundleIdentifier raw '$APP/Contents/Info.plist' | grep -qx dev.gordas.GDCEffectsLibrary && plutil -extract LSMinimumSystemVersion raw '$APP/Contents/Info.plist' | grep -qx 14.0"
step "no personal paths in shipped sources" bash -c "! grep -rE '/Users/gordasgdc|CristiGordas' Sources/EffectsLibrary Sources/EffectsLibraryCore Sources/EffectsLibraryEngine"
step "site checks (anchors, links, no JS, parity, preview state)" python3 scripts/verify-site.py
step "release script does not delete the release folder" bash -c "! grep -nE 'rm -rf +\"?\\$(OUT|REL|GEL_OUT)\"?( |$)' scripts/release.sh"
step "public tree has no personal identifiers" scripts/public-tree.sh check
step "no attribution lines in git history" bash -c "! git log --format=%B 2>/dev/null | grep -qiE 'co-authored-by: *claude|anthropic'"
step "no literal colors outside Theme" bash -c "! grep -rnE 'Color\\((red|\\.sRGB)|Color\\.(black|white|red|blue|green|gray)|\\.foregroundColor\\(\\.(black|white)' Sources/EffectsLibrary | grep -v Theme.swift"
[ $fail -eq 0 ] && echo "PREFLIGHT OK" || { echo "PREFLIGHT FAILED"; exit 1; }
