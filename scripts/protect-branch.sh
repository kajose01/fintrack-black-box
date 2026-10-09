#!/usr/bin/env bash
# Enforce GitHub Flow: PR + approval + passing checks, no force-push. Needs `gh auth login` (repo admin).
# Usage: protect-branch.sh owner/repo [branch]
set -euo pipefail
REPO="${1:?owner/repo}"; BRANCH="${2:-main}"
gh api -X PUT "repos/$REPO/branches/$BRANCH/protection" --input - <<'JSON'
{
  "required_status_checks": {"strict": true, "contexts": ["secret-scan", "validate"]},
  "enforce_admins": false,
  "required_pull_request_reviews": {"required_approving_review_count": 1, "dismiss_stale_reviews": true, "require_code_owner_reviews": true},
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_linear_history": true
}
JSON
echo "protected $REPO:$BRANCH"
