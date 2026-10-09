#!/usr/bin/env bash
# Records release state in a ConfigMap so ANY actor (Jenkins, cron reconciler, human) can roll back to the *last good image*.
# Usage: mark-release.sh stable|deploying|rolled-back|promoted <image>
set -euo pipefail
NS=fintrack; STATUS="$1"; IMAGE="${2:-}"
LAST=$(kubectl -n $NS get cm release-state -o jsonpath='{.data.last_good_image}' 2>/dev/null || true)
LAST=${LAST:-fintrack/app:v1}
case "$STATUS" in stable|promoted) [ -n "$IMAGE" ] && LAST="$IMAGE" ;; esac
kubectl -n $NS create cm release-state --from-literal=status="$STATUS" --from-literal=candidate_image="$IMAGE" \
  --from-literal=last_good_image="$LAST" --from-literal=updated_epoch="$(date +%s)" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
echo "release-state: status=$STATUS candidate=$IMAGE last_good=$LAST"
