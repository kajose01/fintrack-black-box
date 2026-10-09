#!/usr/bin/env bash
# Phase 3 final task: inject a fake failure, watch the mesh absorb it, then verify recovery.
set -uo pipefail
cd "$(dirname "$0")/.."
echo "== baseline =="; scripts/test-traffic.sh 40
echo "== inject: 40% aborts + 30% 2s delays on payment-service =="; kubectl apply -f chaos/fault-payment.yaml
scripts/test-traffic.sh 60
echo "== kill a payment pod during the fault =="; kubectl -n fintrack delete pod -l app=payment-service --wait=false | head -1
sleep 5; scripts/test-traffic.sh 40
echo "== remove fault, verify recovery =="; kubectl apply -f istio/30-routing.yaml
kubectl -n fintrack rollout status deploy/payment-service-v1 --timeout=120s
scripts/test-traffic.sh 60
