#!/bin/bash
# Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
# Reproducible release candidate: Developer ID signing (hardened runtime, secure timestamp), notarization of the app and of the DMG,
# stapling, Gatekeeper and signature verification on the exact artifact. Never installs anything; never touches /Applications.
# Credentials: only the existing Keychain identity and the existing notarytool Keychain profile (no secrets pass through here).
# Usage: scripts/release.sh   (needs a clean Git tree: the candidate is tied to the exact commit)
# Output: $GEL_OUT/release/<version>/attempts/<UTC-stamp>-<commit>/ScanerGDC-macOS-<version>.dmg (+ .sha256, report).
# Every attempt gets its own directory. Nothing from an earlier attempt (candidates, reports, submission IDs, signed packages,
# rollback artifacts) is ever deleted or overwritten. A verified candidate is recorded by appending one line to
# $GEL_OUT/release/<version>/CANDIDATES.tsv (the explicit index); promotion for distribution is a separate, manual decision.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/dev-env.sh
VERSION="$(cat VERSION)"
PROFILE="${NOTARY_PROFILE:-gdc-notary}"
# Signing identity: GEL_SIGN_IDENTITY (scripts/local.env) or, if unset, the single "Developer ID Application" identity in the Keychain.
if [ -z "${GEL_SIGN_IDENTITY:-}" ]; then
  FOUND="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | sort -u)"
  [ "$(printf '%s\n' "$FOUND" | grep -c .)" = 1 ] || { echo "FAIL: set GEL_SIGN_IDENTITY (found: $(printf '%s' "$FOUND" | grep -c .) Developer ID identities)" >&2; exit 1; }
  GEL_SIGN_IDENTITY="$FOUND"
fi
SIGN_ID="$GEL_SIGN_IDENTITY"
[ -z "$(git status --porcelain)" ] || { echo "FAIL: Git tree not clean; commit first so the candidate maps to one commit" >&2; exit 1; }
COMMIT="$(git rev-parse --short=12 HEAD)"
REL="$GEL_OUT/release/$VERSION"; ATTEMPT="$(date -u +%Y%m%dT%H%M%SZ)-$COMMIT"
OUT="$REL/attempts/$ATTEMPT"
[ -e "$OUT" ] && { echo "FAIL: attempt directory already exists: $OUT" >&2; exit 1; }
mkdir -p "$OUT/stage"
REPORT="$OUT/release-report.txt"; : > "$REPORT"
fail() { echo "FAIL: $*" | tee -a "$REPORT" >&2; echo "attempt kept for inspection: $OUT" >&2; exit 1; }
ok() { echo "OK   $*" | tee -a "$REPORT"; }

IDS="$(security find-identity -v -p codesigning)"; grep -qF "$SIGN_ID" <<<"$IDS" || fail "signing identity not available in Keychain: $SIGN_ID"
xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 || fail "notarytool Keychain profile '$PROFILE' not usable"
ok "identity and notary profile available"

# 1. Build + sign the app (bundle folder is named for users: Scaner GDC.app)
GEL_APP_DIR="$OUT/stage" GEL_APP_NAME="Scaner GDC" GEL_SIGN_IDENTITY="$SIGN_ID" scripts/build-app.sh release >/dev/null 2>>"$OUT/build.log" || fail "build/sign failed (see $OUT/build.log)"
APP="$OUT/stage/Scaner GDC.app"
AR="$(lipo -archs "$APP/Contents/MacOS/GDCEffectsLibrary")"; echo "architectures: $AR" >>"$REPORT"; [ "$AR" = "x86_64 arm64" ] || [ "$AR" = "arm64 x86_64" ] || fail "binary is not universal ($AR)"
codesign --verify --strict --deep --verbose=2 "$APP" 2>>"$REPORT" || fail "app signature invalid"
CD="$(codesign -dv --verbose=4 "$APP" 2>&1)"; grep -q "flags=.*runtime" <<<"$CD" || fail "hardened runtime flag missing"
ok "app signed (Developer ID, hardened runtime, timestamp)"
EN="$(codesign -d --entitlements - "$APP" 2>&1 || true)"; if grep -q "<key>" <<<"$EN"; then fail "unexpected entitlements present"; fi; ok "no entitlements (minimal: not sandboxed, no JIT, no special capabilities)"

# 2. Notarize + staple the app
ditto -c -k --keepParent "$APP" "$OUT/app-notarize.zip"
J="$(xcrun notarytool submit "$OUT/app-notarize.zip" --keychain-profile "$PROFILE" --wait --output-format json)" || fail "notarytool (app) failed"
ST="$(printf '%s' "$J" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))')"; ID="$(printf '%s' "$J" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')"
[ "$ST" = "Accepted" ] || { xcrun notarytool log "$ID" --keychain-profile "$PROFILE" 2>&1 | head -40 >>"$REPORT"; fail "app notarization $ST ($ID)"; }
ok "app notarized (submission $ID)"
xcrun stapler staple "$APP" >>"$REPORT" 2>&1 && xcrun stapler validate "$APP" >>"$REPORT" 2>&1 || fail "stapling app failed"
SP="$(spctl -a -vv -t exec "$APP" 2>&1 || true)"; echo "$SP" >>"$REPORT"; grep -q "Notarized Developer ID" <<<"$SP" || fail "Gatekeeper rejects the app"
ok "app stapled; Gatekeeper: Notarized Developer ID"

# 3. DMG: signed, notarized, stapled
DMG="$OUT/ScanerGDC-macOS-$VERSION.dmg"
ln -s /Applications "$OUT/stage/Applications"
hdiutil create -volname "Scaner GDC $VERSION" -srcfolder "$OUT/stage" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null || fail "hdiutil create failed"
codesign --force --sign "$SIGN_ID" --timestamp "$DMG" 2>>"$REPORT" || fail "DMG signing failed"
J="$(xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait --output-format json)" || fail "notarytool (dmg) failed"
ST="$(printf '%s' "$J" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))')"; DID="$(printf '%s' "$J" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')"
[ "$ST" = "Accepted" ] || { xcrun notarytool log "$DID" --keychain-profile "$PROFILE" 2>&1 | head -40 >>"$REPORT"; fail "DMG notarization $ST ($DID)"; }
xcrun stapler staple "$DMG" >>"$REPORT" 2>&1 && xcrun stapler validate "$DMG" >>"$REPORT" 2>&1 || fail "stapling DMG failed"
SP="$(spctl -a -vv -t open --context context:primary-signature "$DMG" 2>&1 || true)"; echo "$SP" >>"$REPORT"; grep -q "Notarized Developer ID" <<<"$SP" || fail "Gatekeeper rejects the DMG"
ok "DMG signed, notarized (submission $DID), stapled, accepted by Gatekeeper"

# 4. Verify as a user would: mount read-only, check the exact bytes shipped
MNT="$(hdiutil attach "$DMG" -nobrowse -readonly 2>>"$REPORT" | awk -F'\t' '/\/Volumes\//{print $NF}' | head -1)"
[ -n "$MNT" ] && [ -d "$MNT" ] || fail "DMG does not mount"
trap 'hdiutil detach "$MNT" -quiet 2>/dev/null || true' EXIT
M="$MNT/Scaner GDC.app"
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$M/Contents/Info.plist")" = "$VERSION" ] || fail "version mismatch inside DMG"
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$M/Contents/Info.plist")" = "dev.gordas.GDCEffectsLibrary" ] || fail "bundle id mismatch"
codesign --verify --strict --deep "$M" || fail "signature of mounted app invalid"
xcrun stapler validate "$M" >/dev/null 2>&1 || fail "mounted app has no notarization ticket"
SP="$(spctl -a -vv -t exec "$M" 2>&1 || true)"; grep -q "Notarized Developer ID" <<<"$SP" || fail "Gatekeeper rejects mounted app"
ok "mounted DMG verified: version $VERSION, bundle id, signature, ticket, Gatekeeper"
hdiutil detach "$MNT" -quiet; trap - EXIT
shasum -a 256 "$DMG" | tee "$DMG.sha256" | tee -a "$REPORT"
# Cleanup is limited to temporaries created by THIS attempt, after verifying the path really is inside this attempt directory.
case "$OUT" in "$GEL_OUT/release/$VERSION/attempts/"*-"$COMMIT") ;; *) fail "refusing cleanup: unexpected path $OUT" ;; esac
[ -d "$OUT/stage" ] && [ ! -L "$OUT/stage" ] && rm -rf "$OUT/stage"
[ -f "$OUT/app-notarize.zip" ] && rm -f "$OUT/app-notarize.zip"
SHA="$(cut -d' ' -f1 "$DMG.sha256")"; SIZE="$(stat -f %z "$DMG")"
printf '%s\t%s\t%s\t%s\t%s\tapp=%s\tdmg=%s\n' "$ATTEMPT" "$VERSION" "$COMMIT" "$SHA" "$SIZE" "$ID" "$DID" >> "$REL/CANDIDATES.tsv"
echo "RELEASE CANDIDATE READY: $DMG" | tee -a "$REPORT"
