#!/bin/bash
# Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
# Builds Scaner GDC (bundle GDCEffectsLibrary-<version>.app). Every generated file goes to external storage (dev-env.sh gate).
# Usage: scripts/build-app.sh [debug|release]   Output: $GEL_BUILD_DIR/GDCEffectsLibrary-<version>.app
# Env: GEL_APP_DIR (output folder, default $GEL_BUILD_DIR), GEL_APP_NAME (bundle folder name, default GDCEffectsLibrary-<version>),
#      GEL_SIGN_IDENTITY ("-" = ad-hoc local signature, default; a Developer ID name = hardened runtime + secure timestamp).
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/dev-env.sh
CONFIG="${1:-release}"
VERSION="$(cat VERSION)"; BUILD="$(cat BUILD_NUMBER)"
ARCHS=()
[ "$CONFIG" = "release" ] && ARCHS=(--arch arm64 --arch x86_64)   # universal binary for release builds
swift build -c "$CONFIG" ${ARCHS[@]+"${ARCHS[@]}"} --scratch-path "$GEL_SCRATCH" >&2
BIN="$(swift build -c "$CONFIG" ${ARCHS[@]+"${ARCHS[@]}"} --scratch-path "$GEL_SCRATCH" --show-bin-path)/GDCEffectsLibrary"
APP="${GEL_APP_DIR:-$GEL_BUILD_DIR}/${GEL_APP_NAME:-GDCEffectsLibrary-$VERSION}.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/GDCEffectsLibrary"
ICON="$(scripts/make-icon.sh)"; cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Scaner GDC</string>
  <key>CFBundleDisplayName</key><string>Scaner GDC</string>
  <key>CFBundleIdentifier</key><string>dev.gordas.GDCEffectsLibrary</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleExecutable</key><string>GDCEffectsLibrary</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Scaner GDC — creat de Cristi Gordaș (GDC).</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
# Default: ad-hoc signature for local runs. Developer ID signing + notarization: scripts/release.sh.
SIGN="${GEL_SIGN_IDENTITY:--}"
if [ "$SIGN" = "-" ]; then codesign --force --sign - "$APP" >&2
else codesign --force --sign "$SIGN" --options runtime --timestamp "$APP" >&2; fi
echo "$APP"
