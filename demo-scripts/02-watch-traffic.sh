#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-medicare-demo-260907-4f00}"
LB_ADDRESS_NAME="${LB_ADDRESS_NAME:-medicare-sp-global-ip}"
INTERVAL="${INTERVAL:-2}"

LB_IP="$(gcloud compute addresses describe "$LB_ADDRESS_NAME" \
  --global \
  --project="$PROJECT_ID" \
  --format='value(address)')"

echo "============================================================"
echo " Medicare HA/DR - Live Traffic Watch"
echo " Global IP: $LB_IP"
echo " Refresh:   ${INTERVAL}s"
echo " Ctrl-C to stop"
echo "============================================================"

while true; do
  echo
  printf '%s  ' "$(date '+%H:%M:%S')"
  PAGE="$(curl -fsS --max-time 5 "http://${LB_IP}/" 2>/dev/null || true)"

  if [[ -z "$PAGE" ]]; then
    echo "REQUEST FAILED / backend transition"
  else
    INSTANCE="$(printf '%s' "$PAGE" | sed -n 's/.*Instance: \([^<]*\).*/\1/p' | head -1)"
    ZONE="$(printf '%s' "$PAGE" | sed -n 's/.*Zone: \([^<]*\).*/\1/p' | head -1)"
    REGION="$(printf '%s' "$PAGE" | sed -n 's/.*Region: \([^<]*\).*/\1/p' | head -1)"

    if [[ -n "$REGION" ]]; then
      echo "region=${REGION} zone=${ZONE} instance=${INSTANCE}"
    else
      echo "response received (old page/template still serving)"
    fi
  fi

  sleep "$INTERVAL"
done
