#!/usr/bin/env bash
# Watches Istio telemetry for the canary (v2). If the 5xx ratio exceeds the threshold -> automatic rollback (exit 1).
# Usage: canary-guard.sh [seconds=120] [threshold_pct=5]
set -uo pipefail
cd "$(dirname "$0")/.."
DUR=${1:-120}; TH=${2:-5}
q() { kubectl -n istio-system exec deploy/prometheus -c prometheus-server -- wget -qO- \
      "http://localhost:9090/api/v1/query?query=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$1")" \
      | python3 -c 'import sys,json;r=json.load(sys.stdin)["data"]["result"];print(r[0]["value"][1] if r else 0)'; }
BASE='istio_requests_total{reporter="destination",destination_service_name="account-service",destination_version="v2"'
end=$((SECONDS+DUR))
while [ $SECONDS -lt $end ]; do
  tot=$(q "sum(rate(${BASE}}[1m]))");  bad=$(q "sum(rate(${BASE},response_code=~\"5..\"}[1m]))")
  pct=$(python3 -c "t=float('$tot');b=float('$bad');print(round(100*b/t,2) if t>0 else 0.0)")
  echo "[$(date +%T)] canary v2: ${pct}% 5xx (threshold ${TH}%)"
  if python3 -c "import sys;sys.exit(0 if float('$pct')>float('$TH') else 1)"; then
    echo "🚨 threshold exceeded -> failing open to v1"; scripts/rollback.sh; exit 1
  fi
  sleep 15
done
echo "canary healthy for ${DUR}s"
