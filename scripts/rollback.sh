#!/usr/bin/env bash
# Fail open to stable: 100% traffic -> v1, canary pods back to the last GOOD image (read from ConfigMap => no tag mismatch).
set -uo pipefail
cd "$(dirname "$0")/.."; NS=fintrack
LAST=$(kubectl -n $NS get cm release-state -o jsonpath='{.data.last_good_image}' 2>/dev/null); LAST=${LAST:-fintrack/app:v1}
echo "ROLLBACK: routing 100% to v1, canary -> $LAST"
kubectl apply -f istio/rollback-v1-only.yaml
kubectl -n $NS set image deploy/account-service-v2 app="$LAST"
kubectl -n $NS rollout status deploy/account-service-v2 --timeout=120s || true
scripts/mark-release.sh rolled-back "$LAST"
