#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-medicare-demo-260907-4f00}"
LB_ADDRESS_NAME="${LB_ADDRESS_NAME:-medicare-sp-global-ip}"
WORKERS="${WORKERS:-30}"
DURATION="${DURATION:-120}"

LB_IP="$(gcloud compute addresses describe "$LB_ADDRESS_NAME" \
  --global \
  --project="$PROJECT_ID" \
  --format='value(address)')"

echo "============================================================"
echo " Medicare HA/DR - Generate Load"
echo " Global IP: $LB_IP"
echo " Workers:   $WORKERS"
echo " Duration:  ${DURATION}s"
echo "============================================================"
echo
echo "Generating HTTP traffic. Keep 05-watch-dr-scale.sh running in another terminal."

for ((i=1; i<=WORKERS; i++)); do
  (
    end=$((SECONDS + DURATION))
    while (( SECONDS < end )); do
      curl -fsS --max-time 3 "http://${LB_IP}/" >/dev/null 2>&1 || true
    done
  ) &
done

wait

echo "Load generation complete."
