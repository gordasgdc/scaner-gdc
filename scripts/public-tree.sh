#!/bin/bash
# Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
# Public tree helper. NEVER pushes anything.
#   check  : verify that the files that would become public contain no personal identifiers/paths/secrets patterns.
#   branch : create a LOCAL orphan branch 'public/<version>' with one commit holding only the public tree (no history rewrite,
#            no remote, no tags; the working tree and current branch are not touched). Review it, then publish only after the author's explicit approval.
set -euo pipefail
cd "$(dirname "$0")/.."
# Paths that stay private (internal state, proposal drafts, internal planning). Everything else tracked is public.
EXCLUDE='^(CLAUDE\.md|docs/INTEGRATION_PLAN\.md|docs/PLAN\.md|scripts/local\.env)'
list() { git ls-files | grep -vE "$EXCLUDE"; }
check() {
  local bad=0
  # personal paths/volume, personal email, legal name, internal registries, key material, attribution lines; the GitHub owner slug in public URLs is intentional.
  if list | grep -vE '^scripts/(public-tree|preflight|verify-site)\.(sh|py)$' | xargs grep -nIE '/Users/gordasgdc|/Volumes/CristiGordas|_codex-supervision|_design-studio|academiagdc|DUMITRU|BEGIN (RSA|EC|PRIVATE)|ghp_|github_pat_|Co-Authored-By|Anthropic'; then bad=1; fi
  [ "$bad" = 0 ] || { echo "public tree check FAILED" >&2; return 1; }
  echo "public tree check OK ($(list | wc -l | tr -d ' ') files)"
}
case "${1:-}" in
  check) check ;;
  branch)
    check
    [ -z "$(git status --porcelain)" ] || { echo "commit first (clean tree required)" >&2; exit 1; }
    V="$(cat VERSION)"; B="${GEL_PUBLIC_BRANCH:-public/$V}"; PARENT_ARGS=(); [ -z "${GEL_PUBLIC_PARENT:-}" ] || PARENT_ARGS=(-p "$GEL_PUBLIC_PARENT")   # a child commit for later site-only updates
    git rev-parse --verify -q "refs/heads/$B" >/dev/null && { echo "branch $B already exists; not overwriting" >&2; exit 1; }
    COMMIT="$(git rev-parse --short=12 HEAD)"
    # Plumbing only: a temporary index, no checkout, the working tree and the current branch are never touched.
    TMPIDX="$(mktemp -u "${TMPDIR:-/tmp}/gel-public-idx.XXXXXX")"
    GIT_INDEX_FILE="$TMPIDX" git read-tree HEAD
    git ls-tree -r --name-only HEAD | grep -E "$EXCLUDE" | GIT_INDEX_FILE="$TMPIDX" xargs -I{} git update-index --force-remove -- "{}"
    TREE="$(GIT_INDEX_FILE="$TMPIDX" git write-tree)"; rm -f "$TMPIDX"
    NEW="$(GIT_AUTHOR_NAME=GDC GIT_AUTHOR_EMAIL=noreply@gordas.dev GIT_COMMITTER_NAME=GDC GIT_COMMITTER_EMAIL=noreply@gordas.dev \
           git commit-tree "$TREE" ${PARENT_ARGS[@]+"${PARENT_ARGS[@]}"} -m "Scaner GDC $V" -m "Source snapshot of the private development history at $COMMIT.")"
    git update-ref "refs/heads/$B" "$NEW"
    git log --format='%h %an <%ae> %s' -1 "$B"
    echo "local branch $B created from $COMMIT (not pushed)" ;;
  *) echo "usage: $0 check|branch" >&2; exit 2 ;;
esac
