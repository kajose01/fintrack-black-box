#!/usr/bin/env bash
# Build once, tag v1 + v2, import into k3s (no registry needed).
set -euo pipefail
docker build -t fintrack/app:v1 app
docker tag fintrack/app:v1 fintrack/app:v2
for t in v1 v2; do docker save fintrack/app:$t | sudo k3s ctr images import -; done
sudo k3s ctr images ls | grep fintrack/app
