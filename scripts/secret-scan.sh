#!/usr/bin/env bash
# Usage: secret-scan.sh --staged | --all | --range <git diff args>
# Same script runs locally (hooks) AND in CI, so bypassing the hook (--no-verify) still gets caught server-side.
set -uo pipefail
PATTERN='AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|dckr_pat_[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|xox[baprs]-[A-Za-z0-9-]{10,}|(password|passwd|secret|api_?key|token)[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9/+_-]{8,}'
EXCLUDE=':!scripts/secret-scan.sh'; EXAMPLES=':!*.example'
mode="${1:---staged}"
case "$mode" in
  --staged) lines=$(git diff --cached -U0 --no-color -- . "$EXCLUDE" "$EXAMPLES" | grep -E '^\+[^+]' || true) ;;
  --range)  lines=$(git diff -U0 --no-color "${@:2}" -- . "$EXCLUDE" "$EXAMPLES" | grep -E '^\+[^+]' || true) ;;
  --all)    lines=$(git ls-files -- . "$EXCLUDE" "$EXAMPLES" | xargs -r grep -nIiE "$PATTERN" || true) ;;
  *) echo "usage: $0 --staged|--all|--range <args>"; exit 2 ;;
esac
hits=$(printf '%s\n' "$lines" | grep -iE "$PATTERN" | grep -v 'pragma: allowlist secret' || true)
if [ -n "$hits" ]; then
  echo "❌ Possible secret(s) detected (values truncated):"
  printf '%s\n' "$hits" | cut -c1-70 | sed 's/$/ .../'
  echo "Remove them, rotate the credential, or add '# pragma: allowlist secret' for a false positive."
  exit 1
fi
echo "✅ secret scan clean ($mode)"
