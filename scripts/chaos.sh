#!/usr/bin/env bash
# Bonus round. Usage: chaos.sh jenkins-crash | secret-bypass | canary-100
set -uo pipefail
cd "$(dirname "$0")/.."
case "${1:-}" in
 jenkins-crash)   # 1. agent dies mid-deploy
   scripts/mark-release.sh deploying fintrack/app:v2
   kubectl -n fintrack set image deploy/account-service-v2 app=fintrack/app:v2-does-not-exist
   docker kill jenkins-agent 2>/dev/null || echo "(no agent container; pretend it died here)"
   echo "Deploy is half-done and nobody is watching. Reconciler (cron) should notice:"; MAX_MIN=0 scripts/reconcile.sh ;;
 secret-bypass)   # 2. developer bypasses the local hook
   git checkout -q -b chaos/secret-bypass
   printf 'aws_key=%s\n' "AKIA$(echo IOSFODNN7EXAMPLE)" > leaked.env && git add leaked.env
   git commit --no-verify -qm "oops: bypass hook" && echo "hook bypassed locally -> CI secret-scan (required check) will block the PR:"
   scripts/secret-scan.sh --range HEAD~1 HEAD; git reset -q --hard HEAD~1; git checkout -q -; git branch -D chaos/secret-bypass -q ;;
 canary-100)      # 3. buggy v2 receives 100%
   kubectl -n fintrack set env deploy/account-service-v2 FAIL_RATE=0.6
   kubectl -n fintrack rollout status deploy/account-service-v2 --timeout=120s
   kubectl patch virtualservice account-service -n fintrack --type=json -p \
     '[{"op":"replace","path":"/spec/http/0/route/0/weight","value":0},{"op":"replace","path":"/spec/http/0/route/1/weight","value":100}]'
   (scripts/test-traffic.sh 60 &) ; sleep 2
   scripts/canary-guard.sh 90 5 ;;
 *) echo "usage: $0 jenkins-crash|secret-bypass|canary-100"; exit 2 ;;
esac
