#!/usr/bin/env bash
# Usage: test-traffic.sh [N=100]   -> status-code histogram + which account-service versions served
N=${1:-100}; URL=${URL:-http://localhost:30090/}
codes=""; v1=0; v2=0
for i in $(seq "$N"); do
  out=$(curl -s -m 5 -w '\n%{http_code}' "$URL"); code=${out##*$'\n'}; body=${out%$'\n'*}
  codes="$codes $code"
  case "$body" in *'"service": "account-service", "version": "v2"'*) v2=$((v2+1));; *'"service": "account-service", "version": "v1"'*) v1=$((v1+1));; esac
done
echo "status codes:"; echo $codes | tr ' ' '\n' | sort | uniq -c
echo "account-service served by: v1=$v1 v2=$v2"
