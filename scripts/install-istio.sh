#!/usr/bin/env bash
# Run on the server (needs kubectl + internet). Installs istioctl, Istio (NodePort gateway :30090), Prometheus + Jaeger addons.
set -euo pipefail
cd ~; [ -d istio-dl ] || { mkdir istio-dl; cd istio-dl; curl -L https://istio.io/downloadIstio | sh -; cd ~; }
IDIR=$(ls -d ~/istio-dl/istio-* | head -1)
sudo ln -sf "$IDIR/bin/istioctl" /usr/local/bin/istioctl
istioctl version --remote=false
cd - >/dev/null
istioctl install -f istio/00-install.yaml -y
kubectl apply -f "$IDIR/samples/addons/prometheus.yaml" -f "$IDIR/samples/addons/jaeger.yaml"
kubectl -n istio-system rollout status deploy/istiod deploy/prometheus deploy/jaeger --timeout=300s
