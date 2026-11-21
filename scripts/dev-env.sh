#!/bin/bash
# Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
# Development-environment configuration (NOT part of the shipped product).
# Source this file: it applies the external-storage gate (STORAGE_POLICY.md) and exports build paths.
# If the external volume is not mounted+writable: prints the required message and returns/exit 3. No fallback.
# Machine-specific values live in scripts/local.env (git-ignored; template: scripts/local.env.example).
[ -f "$(dirname "${BASH_SOURCE[0]:-$0}")/local.env" ] && . "$(dirname "${BASH_SOURCE[0]:-$0}")/local.env"
if [ -z "${GDC_EXTERNAL_ROOT:-}" ]; then
  echo "GDC_EXTERNAL_ROOT is not set: copy scripts/local.env.example to scripts/local.env and edit it" >&2
  return 3 2>/dev/null || exit 3
fi
EXTERNAL_ROOT="$GDC_EXTERNAL_ROOT"
GEL_OUT="$EXTERNAL_ROOT/GDC_PROJECTS/GDC_EFFECTS_LIBRARY"

gel_gate() {
  local vol; vol="/Volumes/$(echo "$EXTERNAL_ROOT" | cut -d/ -f3)"
  if ! mount | grep -q " on $vol " || ! touch "$EXTERNAL_ROOT/.gel_gate" 2>/dev/null; then
    echo "EXTERNAL TEST STORAGE NOT AVAILABLE" >&2
    return 3
  fi
  rm -f "$EXTERNAL_ROOT/.gel_gate"
  mkdir -p "$GEL_OUT"/{builds,cache,evidence,benchmarks,artifacts,temp}
}

gel_gate || { return 3 2>/dev/null || exit 3; }

export GEL_OUT
export GEL_BUILD_DIR="$GEL_OUT/builds"
export GEL_SCRATCH="$GEL_OUT/builds/swiftpm"
export GEL_EVIDENCE="$GEL_OUT/evidence"
export TMPDIR="$GEL_OUT/temp/"
export CLANG_MODULE_CACHE_PATH="$GEL_OUT/cache/clang-modules"
export SWIFTPM_MODULECACHE_OVERRIDE="$GEL_OUT/cache/swiftpm-modules"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p "$TMPDIR" "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE"
