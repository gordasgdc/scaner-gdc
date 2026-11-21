#!/bin/bash
# Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
# Reproducible icon build: approved SVG master -> iconset -> .icns. Outputs on external storage only.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/dev-env.sh
MASTER="${GEL_ICON_MASTER:-branding/neutral-icon.svg}"   # official builds set GEL_ICON_MASTER=branding/scaner-gdc-logo.svg (see branding/BRANDING.md)
[ -f "$MASTER" ] || { echo "master SVG missing: $MASTER" >&2; exit 2; }
D="$GEL_OUT/artifacts/icon"; rm -rf "$D"; mkdir -p "$D"
swift scripts/make-icon.swift "$MASTER" "$D/AppIcon.iconset" >&2
iconutil -c icns "$D/AppIcon.iconset" -o "$D/AppIcon.icns"
shasum -a 256 "$MASTER" > "$D/master.sha256"
echo "$D/AppIcon.icns"
