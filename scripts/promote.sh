#!/usr/bin/env bash
# Progressive promotion 25% -> 50% with the guard watching between steps. Runs only after human approval in Jenkins.
set -euo pipefail
cd "$(dirname "$0")/.."; IMAGE="${1:?image}"
for w in 25 50; do
  echo "canary weight -> ${w}%"
  kubectl -n fintrack patch virtualservice account-service --type=json -p \
   "[{\"op\":\"replace\",\"path\":\"/spec/http/0/route/0/weight\",\"value\":$((100-w))},{\"op\":\"replace\",\"path\":\"/spec/http/0/route/1/weight\",\"value\":$w}]"
  scripts/canary-guard.sh 60 5
done
scripts/mark-release.sh promoted "$IMAGE"
