#!/usr/bin/env bash
# Builds a throw-away repo that reproduces "release night": a bad commit + a committed secret, then fixes both.
set -euo pipefail
D=/tmp/fintrack-release-demo; rm -rf "$D"; mkdir -p "$D"; cd "$D"
git init -q -b main; git config user.email dev@fintrack.test; git config user.name "FinTrack Dev"
cat > check.sh <<'X'
#!/bin/sh
# exit 0 = good, 1 = bad  (used by git bisect run)
. ./app.env && [ "$TIMEOUT_MS" -le 3000 ]
X
chmod +x check.sh
echo "TIMEOUT_MS=1000" > app.env;  git add -A; git commit -qm "feat: baseline config"
echo "# readme" > README.md;        git add -A; git commit -qm "docs: add readme"
echo "FEATURE_X=on" >> app.env;     git add -A; git commit -qm "feat: toggle feature X via env"
echo "TIMEOUT_MS=90000" > app.env;  git add -A; git commit -qm "perf: tune timeout"          # <-- BAD commit
FAKE="AKIA$(echo IOSFODNN7EXAMPLE)"
mkdir config; printf 'AWS_KEY=%s\n' "$FAKE" > config/prod.env
git add -A; git commit -qm "chore: add prod config"                                       # <-- committed secret
echo "LOG=info" > log.env;          git add -A; git commit -qm "feat: log level"
echo "=== history ==="; git log --oneline
echo; echo "=== 1a. FIND the bad commit automatically (git bisect run) ==="
ROOT=$(git rev-list --max-parents=0 HEAD)
git bisect start HEAD "$ROOT" >/dev/null
git bisect run ./check.sh | grep -E "is the first bad commit|^commit|    perf" | head -3
BAD=$(git rev-parse refs/bisect/bad); git bisect reset >/dev/null 2>&1
echo; echo "=== 1b. UNDO without rewriting shared history (git revert) ==="
git revert --no-edit "$BAD" >/dev/null && ./check.sh && echo "check passes again"; git log --oneline | head -3
echo; echo "=== reflog = safety net (shows every HEAD move) ==="; git reflog | head -5
echo; echo "=== 1c. SECRET: purge from history, then ROTATE the key (history rewrite needs a coordinated force-push) ==="
git filter-branch -f --index-filter 'git rm -q --cached --ignore-unmatch config/prod.env' -- --all >/dev/null 2>&1
git for-each-ref --format='%(refname)' refs/original | xargs -r -n1 git update-ref -d
git reflog expire --expire=now --all; git gc -q --prune=now
echo "secret still in history? -> $(git log -p --all | grep -c "$FAKE") hits"
