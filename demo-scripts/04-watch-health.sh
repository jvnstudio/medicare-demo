#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-medicare-demo-260907-4f00}"
BACKEND_SERVICE="${BACKEND_SERVICE:-medicare-sp-portal-backend}"
INTERVAL="${INTERVAL:-5}"

echo "============================================================"
echo " Medicare HA/DR - Backend Health Watch"
echo " Backend: $BACKEND_SERVICE"
echo " Ctrl-C to stop"
echo "============================================================"

while true; do
  clear
  date
  echo
  gcloud compute backend-services get-health "$BACKEND_SERVICE" \
    --global \
    --project="$PROJECT_ID" || true
  sleep "$INTERVAL"
done
