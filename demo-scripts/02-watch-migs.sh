#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-medicare-demo-260907-4f00}"
PRIMARY_REGION="${PRIMARY_REGION:-us-east4}"
DR_REGION="${DR_REGION:-us-central1}"
PRIMARY_MIG="${PRIMARY_MIG:-medicare-sp-portal-primary}"
DR_MIG="${DR_MIG:-medicare-sp-portal-dr}"
INTERVAL="${INTERVAL:-2}"

show_mig() {
  local title="$1"
  local mig="$2"
  local region="$3"

  echo "$title"
  gcloud compute instance-groups managed list-instances "$mig" \
    --region="$region" \
    --project="$PROJECT_ID" \
    --format="table(instance.basename():label=INSTANCE,instance.scope(zone):label=ZONE,instanceStatus:label=STATUS,currentAction:label=ACTION,healthState:label=HEALTH)" || true
}

echo "============================================================"
echo " Medicare HA/DR - Live MIG Watch"
echo " Primary: $PRIMARY_MIG ($PRIMARY_REGION)"
echo " DR:      $DR_MIG ($DR_REGION)"
echo " Refresh: ${INTERVAL}s"
echo " Ctrl-C to stop"
echo "============================================================"
sleep 2

while true; do
  clear
  date
  echo
  show_mig "PRIMARY MIG - $PRIMARY_REGION" "$PRIMARY_MIG" "$PRIMARY_REGION"
  echo
  show_mig "DR MIG - $DR_REGION" "$DR_MIG" "$DR_REGION"
  echo
  echo "Watch STATUS / ACTION / HEALTH while another terminal deletes a primary VM."
  sleep "$INTERVAL"
done
