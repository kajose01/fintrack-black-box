# Troubleshooting Report: FinTrack Release Night

> Add your own command output / screenshots under each step. Commands are listed so you can reproduce them.

## Phase 1: Git hygiene & release management
**Find the bad commit:** `scripts/phase1-simulate.sh` reproduces the release, then `git log --oneline`, `git diff`, and `git bisect start HEAD <root>` + `git bisect run ./check.sh` find `perf: tune timeout` automatically.
**Undo safely:** `git revert <sha>` (new commit, shared history untouched). `git reset --hard`/`--amend` only on unpushed local work. `git reflog` recovers anything lost.
**Secret in history:** (1) ROTATE the credential first, (2) purge with `git filter-branch --index-filter 'git rm --cached --ignore-unmatch <file>' -- --all`, expire reflog, gc, (3) coordinated force-push, everyone re-clones. Rotation matters more than the purge: anything pushed must be treated as public.
**GitHub Flow:** `scripts/protect-branch.sh owner/repo` (PR + 1 approval + code-owner review + required checks `secret-scan`,`validate` + no force-push). Branch `release/2026.10.1`, tag `release/2026.10.1`.
**Changelog + tag deploy:** `.github/workflows/release.yml` runs `scripts/changelog.sh` on every `release/*` tag and publishes a GitHub Release.
**Hook:** `.githooks/pre-commit` and `pre-push` (`git config core.hooksPath .githooks`). **Approval-required PR checks:** `.github/workflows/pr-checks.yml` + CODEOWNERS + branch protection.
Note: a solo account cannot approve its own PR; use a second account/collaborator or keep `enforce_admins:false`.

## Phase 2: Jenkins
| Question | How to check (`scripts/jenkins-diagnose.sh`) | Fix |
|---|---|---|
| Docker builds overloading? | `docker stats`, OOM flag in `docker inspect` | memory/CPU limits on controller (1.5 G) and agent (1 G); `numExecutors: 0` on controller |
| Disk full? | `df -h`, `docker system df` | `docker builder prune`, `image prune --filter until=...`, `buildDiscarder`, pipeline `post { always { prune } }` |
| Agent disconnected? | agent container logs | `restart: unless-stopped`, WebSocket agent, healthcheck-gated start |
**Rollback tag mismatch:** old pipeline rolled back to a tag guessed at build time. Now `release-state` ConfigMap stores `last_good_image` (written only on successful promote), and `scripts/rollback.sh` sets the canary back to *that* image and routes 100% to v1.
**Conditional rollback on 5xx:** `scripts/canary-guard.sh` queries Prometheus (`istio_requests_total`, `destination_version="v2"`, `response_code=~"5.."`) and rolls back above 5%.
**Timeouts/notifications:** global 25 min timeout, stage timeouts, `post { failure/aborted }` -> rollback + webhook notification.
**Security:** JCasC matrix auth (admin vs dev read/build), `input submitter: 'admin,release-managers'` gate before promotion, credentials in the Jenkins credentials store fed from an ignored `.env` (rotate = edit `.env` + `docker compose up -d`).
*Not executed in my sandbox: the Jenkins stack needs your server. Report any plugin/compose error and it will be adjusted.*

## Phase 3: Docker / Kubernetes
**OOMKilled:** `kubectl apply -f broken/oom-ledger.yaml`; `kubectl -n fintrack get pods` (CrashLoopBackOff); `kubectl -n fintrack logs <pod> --previous`; `kubectl -n fintrack describe pod <pod>` -> `Reason: OOMKilled, Exit Code 137`. Fix: `kubectl -n fintrack set env deploy/ledger-service-v1 AUTO_LEAK_MB=20` (the leak) and `kubectl -n fintrack set resources deploy/ledger-service-v1 --limits=memory=128Mi,cpu=250m`. Retry strategy: `progressDeadlineSeconds: 120`, probes, Istio retries.
**ImagePullBackOff:** `broken/imagepull-account-v3.yaml` -> `describe pod` shows `manifest unknown`/`not found` for a typo'd tag. Fix: correct tag (`kubectl -n fintrack set image deploy/account-service-v3 app=fintrack/app:v2`), or delete.
**Mongo Pending:** `broken/mongo-pending.yaml` -> `kubectl -n fintrack describe pvc data-mongo-broken-0` ("storageclass fast-ssd not found"); `describe pod mongo-broken-1` ("didn't match pod anti-affinity rules"). Checks: `kubectl get storageclass`, volume binding mode (local-path = WaitForFirstConsumer, binds when the pod schedules). Fix (`k8s/10-mongo.yaml`): existing class `local-path`, `preferred` anti-affinity.
**Canary mismatch:** `kubectl apply -f broken/canary-misrouted.yaml` -> 503 `no healthy upstream` for 100% of traffic. Diagnose: `istioctl analyze -n fintrack`, `kubectl -n fintrack get pods --show-labels`, `istioctl proxy-config endpoints deploy/frontend-v1.fintrack | grep account`. Root cause: pod `version` label != DestinationRule subset label. Fix: `kubectl apply -f istio/30-routing.yaml`. Prevention: `scripts/validate-istio.py` rejects canary weight > 25 in git.
**Quotas:** `k8s/00-namespace.yaml` ResourceQuota (cpu/mem/pods/PVCs) + LimitRange defaults; test with `kubectl -n fintrack describe quota`.
**Fault injection + recovery:** `scripts/fault-injection.sh` (40% aborts, 30% 2 s delays on payment-service; retries and ejection absorb it; fault removed; traffic returns to 200s).

## Phase 4: Istio
mTLS: `istio/10-mesh.yaml` STRICT mesh-wide (verify: `kubectl run -n default curl --image=curlimages/curl -it --rm -- curl -s http://account-service.fintrack:8080` fails without a sidecar).
Canary 90/10 + retries(2) + timeout(3 s): `istio/30-routing.yaml` (`scripts/test-traffic.sh 100`).
Circuit breaker: payment-service `outlierDetection` (5 consecutive 5xx -> ejected 60 s, max 50%).
Tracing: Telemetry + Jaeger extension provider, 100% sampling; apps forward B3 headers. `kubectl -n istio-system port-forward svc/tracing 16686:80`, search service `frontend`.
**Where is the latency?** The Jaeger trace shows frontend -> account (small) -> payment-service with a ~400 ms span, nearly all of the end-to-end time. Optimization applied: `kubectl -n fintrack set env deploy/payment-service-v1 DELAY_MS=50` (simulating caching/query fix), plus retries kept at 2 with `perTryTimeout: 1s` so retries cannot multiply latency.

## Bonus: chaos & prevention
1. **Jenkins agent crashes mid-deploy** (`scripts/chaos.sh jenkins-crash`). Expected: state was recorded as `deploying` *before* the deploy, so an independent reconciler (`scripts/reconcile.sh` via cron) sees a deploy stuck > N minutes and runs the same rollback. Improvements: idempotent `kubectl apply`, `rollout status --timeout`, `progressDeadlineSeconds`, agent auto-restart, rollback decided from cluster state not Jenkins state.
2. **Secret committed again, hook bypassed** (`scripts/chaos.sh secret-bypass`). Trust-but-verify: local hook (convenience) + identical scan as a *required* CI check (cannot be bypassed with `--no-verify`) + branch protection + enable GitHub secret scanning/push protection + rotate immediately on detection.
3. **Istio pushes 100% to buggy v2** (`scripts/chaos.sh canary-100`). `canary-guard.sh` detects >5% 5xx within ~15 s and fails open to 100% v1; git policy blocks canary weights > 25; promotion is stepwise (25 -> 50) with guard between steps and human approval; outlier detection ejects bad pods; v2 stays small by default.
