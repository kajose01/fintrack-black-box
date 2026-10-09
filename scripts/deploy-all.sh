#!/usr/bin/env bash
set -euo pipefail
kubectl apply -f k8s/00-namespace.yaml
# secrets are generated on the cluster, never committed
kubectl -n fintrack get secret mongo-credentials >/dev/null 2>&1 || \
  kubectl -n fintrack create secret generic mongo-credentials --from-literal=username=fintrack --from-literal="password=$(openssl rand -hex 16)"
kubectl apply -f k8s/
kubectl apply -f istio/10-mesh.yaml -f istio/20-gateway.yaml -f istio/30-routing.yaml
scripts/mark-release.sh stable fintrack/app:v1
for d in frontend-v1 account-service-v1 account-service-v2 payment-service-v1; do kubectl -n fintrack rollout status deploy/$d --timeout=180s; done
kubectl -n fintrack get pods,pvc
