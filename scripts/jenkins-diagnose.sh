#!/usr/bin/env bash
# Phase 2.1: is the agent offline because of disk, overload or disconnect?
echo "== disk =="; df -h / | tail -1; docker system df
echo "== memory/cpu =="; free -h | head -2; docker stats --no-stream --format '{{.Name}} cpu={{.CPUPerc}} mem={{.MemUsage}}' 2>/dev/null
echo "== containers =="; docker ps -a --filter name=jenkins --format '{{.Names}}  {{.Status}}'
echo "== agent log (last 15) =="; docker logs --tail 15 jenkins-agent 2>&1
echo "== OOM kills =="; docker inspect -f '{{.Name}} oom={{.State.OOMKilled}} restarts={{.RestartCount}}' jenkins jenkins-agent 2>/dev/null
echo "== fix: reclaim disk (safe) =="; echo "docker builder prune -af --filter until=24h && docker image prune -af --filter until=48h"
