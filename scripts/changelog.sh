#!/usr/bin/env bash
# Usage: changelog.sh release/2026.10.1   -> prints markdown changelog since previous release/* tag
set -euo pipefail
TAG="${1:?tag}"
PREV=$(git describe --tags --abbrev=0 --match 'release/*' "${TAG}^" 2>/dev/null || true)
RANGE=${PREV:+$PREV..}$TAG
echo "## $TAG ($(date -u +%F))"; echo
[ -n "$PREV" ] && echo "Changes since \`$PREV\`:" || echo "Initial release:"; echo
git log --no-merges --pretty='- %s (%h, %an)' "$RANGE"
