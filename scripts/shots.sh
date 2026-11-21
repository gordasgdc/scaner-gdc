#!/bin/bash
# Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
# Verification screenshots of the real app window on a synthetic library. Evidence goes to external storage only.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/dev-env.sh
APP="$(scripts/build-app.sh 2>>"$GEL_EVIDENCE/build-app.log")"
SWIFT_WIN="$TMPDIR/winid.swift"
cat > "$SWIFT_WIN" <<'S'
import CoreGraphics
import Foundation
let pid = Int32(CommandLine.arguments[1])!
let l = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in l where (w[kCGWindowOwnerPID as String] as? Int32) == pid && (w[kCGWindowLayer as String] as? Int) == 0 { print(w[kCGWindowNumber as String]!); break }
S
swift build --scratch-path "$GEL_SCRATCH" --product gel-bench >/dev/null 2>&1
BIN="$(swift build --scratch-path "$GEL_SCRATCH" --show-bin-path)/gel-bench"
# Neutral demo volume so no personal path or volume name appears in screenshots (/Volumes/ScanerDemo/...).
IMG="$GEL_OUT/temp/demo.sparseimage"; rm -f "$IMG"
hdiutil create -size 300m -fs APFS -volname ScanerDemo -type SPARSE "$IMG" >/dev/null 2>&1
DEMO="$(hdiutil attach "$IMG" -nobrowse -plist | grep -o '/Volumes/ScanerDemo[^<]*' | head -1)"
trap 'hdiutil detach "$DEMO" -force >/dev/null 2>&1 || true; rm -f "$IMG"' EXIT
LIB="$DEMO/Library"
rm -rf "$GEL_OUT/temp/shots-storage"
"$BIN" fixtures "$LIB" "$GEL_OUT/temp/shots-storage" >/dev/null
"$BIN" demo-disable "$GEL_OUT/temp/shots-storage" "OFX Effect 3" "$LIB" >/dev/null
export GEL_STORAGE_ROOT="$GEL_OUT/temp/shots-storage" GEL_NO_STANDARD=1 GEL_NO_HOSTS=1
shot() { local name=$1; shift; local sel=$1; shift; local pend=$1; shift
  GEL_SELECT="$sel" GEL_PENDING="$pend" "$APP/Contents/MacOS/GDCEffectsLibrary" "$@" >/dev/null 2>&1 & local pid=$!
  sleep 5; local wid; wid=$(swift "$SWIFT_WIN" $pid 2>&1 | tail -1)
  screencapture -x -o -l "$wid" "$GEL_EVIDENCE/$name.png"; kill $pid 2>/dev/null || true; sleep 1; }
shot shot-inspector-lut Look_1 "" -appearance dark -textSize normal
shot shot-inspector-bundle "AU_Plugin_2" "" -appearance dark -textSize normal
shot shot-confirm-disable "OFX_Effect_1" disable -appearance dark -textSize normal
shot shot-light-normal Look_1 "" -appearance light -textSize normal
shot shot-site-main Look_1 "" -appearance dark -textSize normal
# Product cover/details: synthetic seed only (no third-party image, no network): a generated gradient and invented example text.
PST="$GEL_OUT/temp/shots-storage-product"; rm -rf "$PST"; cp -R "$GEL_OUT/temp/shots-storage" "$PST"; mkdir -p "$PST/support/covers-user"
python3 scripts/seed-demo-product.py "$PST" "ofx|com.synthetic.ofx1" >/dev/null
OLD_ROOT="$GEL_STORAGE_ROOT"; export GEL_STORAGE_ROOT="$PST"
shot shot-product OFX_Effect_1 "" -appearance dark -textSize normal
shot shot-product-consent OFX_Effect_1 consent -appearance dark -textSize normal
shot shot-product-associate OFX_Effect_1 associate -appearance dark -textSize normal
shot shot-product-batch OFX_Effect_2 batch -appearance dark -textSize normal
export GEL_STORAGE_ROOT="$OLD_ROOT"
GEL_SIDEBAR=disabled shot shot-disabled "OFX_Effect_3" "" -appearance dark -textSize normal
GEL_SIDEBAR=activity shot shot-activity "" "" -appearance dark -textSize normal
shot shot-dark-xl "OFX_Effect_1" "" -appearance dark -textSize extraLarge
# About panel (shows the app icon at large size) — capture every on-screen window of the app
GEL_SHOW_ABOUT=1 "$APP/Contents/MacOS/GDCEffectsLibrary" -appearance dark >/dev/null 2>&1 & apid=$!
sleep 5; i=0
for w in $(swift - <<S 2>/dev/null
import CoreGraphics
import Foundation
let l = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in l where (w[kCGWindowOwnerPID as String] as? Int32) == $apid && (w[kCGWindowLayer as String] as? Int) == 0 { print(w[kCGWindowNumber as String]!) }
S
); do i=$((i+1)); screencapture -x -o -l "$w" "$GEL_EVIDENCE/shot-about-$i.png"; done
kill $apid 2>/dev/null || true
echo done
