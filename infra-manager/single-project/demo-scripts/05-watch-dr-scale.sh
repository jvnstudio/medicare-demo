#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-medicare-demo-260907-4f00}"
DR_REGION="${DR_REGION:-us-central1}"
DR_MIG="${DR_MIG:-medicare-sp-portal-dr}"
DR_AUTOSCALER="${DR_AUTOSCALER:-medicare-sp-dr-autoscaler}"
INTERVAL="${INTERVAL:-5}"

echo "============================================================"
echo " Medicare HA/DR - DR Autoscaling Watch"
echo " DR MIG:        $DR_MIG"
echo " DR Autoscaler: $DR_AUTOSCALER"
echo " Ctrl-C to stop"
echo "============================================================"

while true; do
  clear
  date
  echo
  echo "DR INSTANCES"
  gcloud compute instance-groups managed list-instances "$DR_MIG" \
    --region="$DR_REGION" \
    --project="$PROJECT_ID" \
    --format="table(instance.basename():label=INSTANCE,instance.scope(zone):label=ZONE,instanceStatus:label=STATUS,currentAction:label=ACTION,healthState:label=HEALTH)" || true

  echo
  echo "AUTOSCALER"
  gcloud compute instance-groups managed describe "$DR_MIG" \
    --region="$DR_REGION" \
    --project="$PROJECT_ID" \
    --format="yaml(targetSize,status,autoscaler)" 2>/dev/null || true

  echo
  gcloud compute instance-groups managed list "$DR_MIG" \
    --regions="$DR_REGION" \
    --project="$PROJECT_ID" \
    --format="table(name,targetSize,status.isStable)" 2>/dev/null || true

  sleep "$INTERVAL"
done
