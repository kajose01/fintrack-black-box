#!/usr/bin/env bash
# Safety net independent of Jenkins: if a deploy is stuck in 'deploying' > MAX minutes (agent died mid-deploy), roll back.
# Cron:  */5 * * * * cd ~/fintrack && ./scripts/reconcile.sh >> /tmp/reconcile.log 2>&1
set -uo pipefail
cd "$(dirname "$0")/.."; MAX=${MAX_MIN:-10}
st=$(kubectl -n fintrack get cm release-state -o jsonpath='{.data.status}' 2>/dev/null || echo none)
ts=$(kubectl -n fintrack get cm release-state -o jsonpath='{.data.updated_epoch}' 2>/dev/null || echo 0)
age=$(( ($(date +%s)-ts)/60 ))
echo "[$(date +%T)] status=$st age=${age}m"
if [ "$st" = "deploying" ] && [ "$age" -ge "$MAX" ]; then echo "stuck deploy -> rollback"; scripts/rollback.sh; fi
