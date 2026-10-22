#!/usr/bin/env bash
# Prove scripts/fetch_release_tag.sh gives the release workflow's
# annotated-tag assert a tag object, and leaves a lightweight tag a commit.
#
# Reproduces what actions/checkout@v5 does on a tag push with default inputs:
# a depth-1 fetch of the event SHA onto refs/tags/<name> (ref-helper.ts
# getRefSpec: `+<commit>:refs/tags/<name>`), then `git checkout --force`.
#
# Usage: scripts/test_fetch_release_tag.sh
set -euo pipefail

scripts=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com \
       GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
origin="file://$work/origin"

git init -q -b main "$work/origin"
git -C "$work/origin" commit -q --allow-empty -m "Closeout merge"
git -C "$work/origin" tag -a v9.9 -m "M99 — annotated"
git -C "$work/origin" tag v9.8

fail() { echo "FAIL: $*" >&2; exit 1; }

expect() {
  local what=$1 want=$2 got=$3
  [ "$got" = "$want" ] || fail "$what: expected '$want', got '$got'"
}

checkout() {
  local tag=$1 clone=$work/clone-$1
  local sha
  sha=$(git -C "$work/origin" rev-parse "$tag^{commit}")
  git init -q "$clone"
  git -C "$clone" remote add origin "$origin"
  git -C "$clone" -c protocol.version=2 fetch -q --no-tags --prune \
    --no-recurse-submodules --depth=1 origin "+$sha:refs/tags/$tag"
  git -C "$clone" checkout -q --force "refs/tags/$tag"
  echo "$clone"
}

clone=$(checkout v9.9)
expect "annotated tag right after checkout (the bug being fixed)" \
  commit "$(git -C "$clone" cat-file -t v9.9)"
(cd "$clone" && "$scripts/fetch_release_tag.sh" v9.9)
expect "annotated tag after the fetch" tag "$(git -C "$clone" cat-file -t v9.9)"
expect "release title from the annotated tag" "M99 — annotated" \
  "$(git -C "$clone" tag -l --format='%(contents:subject)' v9.9)"
expect "annotated tag still points at the checked-out commit" \
  "$(git -C "$clone" rev-parse HEAD)" "$(git -C "$clone" rev-parse 'v9.9^{commit}')"

clone=$(checkout v9.8)
(cd "$clone" && "$scripts/fetch_release_tag.sh" v9.8)
expect "lightweight tag after the fetch" commit "$(git -C "$clone" cat-file -t v9.8)"

echo "ok: annotated tag dereferences to a tag object, lightweight to a commit"
