#!/bin/sh
# Replace the commit that actions/checkout put on refs/tags/<tag> with the
# tag's own object from origin, so `git cat-file -t <tag>` and
# `%(contents:subject)` see an annotated tag as a tag.
#
# Usage: scripts/fetch_release_tag.sh <tag>
set -eu
tag=$1
git fetch --no-tags origin "+refs/tags/$tag:refs/tags/$tag"
