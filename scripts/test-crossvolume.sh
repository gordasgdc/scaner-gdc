#!/bin/bash
# Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
# Real cross-volume test: creates an APFS disk image on external storage, mounts it as a second volume,
# and runs the CrossVolume tests against it. Nothing touches the owner's real plugins or the internal disk.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/dev-env.sh
IMG="$GEL_OUT/temp/xvol.sparseimage"
rm -f "$IMG"
hdiutil create -size 200m -fs APFS -volname GELXVOL -type SPARSE "$IMG" >/dev/null
MNT="$(hdiutil attach "$IMG" -nobrowse -plist | grep -o '/Volumes/GELXVOL[^<]*' | head -1)"
trap 'hdiutil detach "$MNT" -force >/dev/null 2>&1 || true; rm -f "$IMG"' EXIT
echo "mounted $MNT"
GEL_XVOL="$MNT" swift test --scratch-path "$GEL_SCRATCH" --filter CrossVolumeRealTests 2>&1 | grep -E "error:|✘|✔ Test run|passed|failed" | tail -8
