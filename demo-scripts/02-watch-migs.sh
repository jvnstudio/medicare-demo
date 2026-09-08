#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-medicare-demo-260907-4f00}"
PRIMARY_REGION="${PRIMARY_REGION:-us-east4}"
DR_REGION="${DR_REGION:-us-central1}"
PRIMARY_MIG="${PRIMARY_MIG:-medicare-sp-portal-primary}"
DR_MIG="${DR_MIG:-medicare-sp-portal-dr}"
INTERVAL="${INTERVAL:-2}"

export PROJECT_ID PRIMARY_REGION DR_REGION PRIMARY_MIG DR_MIG

cat <<EOF
============================================================
 Medicare HA/DR - Live MIG Dashboard
 Primary: $PRIMARY_MIG ($PRIMARY_REGION)
 DR:      $DR_MIG ($DR_REGION)
 Refresh: ${INTERVAL}s

 The screen stays in place and refreshes automatically.
 Changed STATUS / ACTION / HEALTH fields are highlighted.
 Press Ctrl-C to stop.
============================================================
EOF
sleep 2

watch -n "$INTERVAL" -d bash -c '
  printf "MEDICARE HA/DR - MANAGED INSTANCE GROUPS\n"
  printf "Last refresh: %s\n\n" "$(date)"

  printf "================ PRIMARY MIG - %s ================\n" "$PRIMARY_REGION"
  gcloud compute instance-groups managed list-instances "$PRIMARY_MIG" \
    --region="$PRIMARY_REGION" \
    --project="$PROJECT_ID" \
    --format="table(instance.basename():label=INSTANCE,instance.scope(zone):label=ZONE,instanceStatus:label=STATUS,currentAction:label=ACTION,healthState:label=HEALTH)" 2>/dev/null || true

  printf "\n================== DR MIG - %s ==================\n" "$DR_REGION"
  gcloud compute instance-groups managed list-instances "$DR_MIG" \
    --region="$DR_REGION" \
    --project="$PROJECT_ID" \
    --format="table(instance.basename():label=INSTANCE,instance.scope(zone):label=ZONE,instanceStatus:label=STATUS,currentAction:label=ACTION,healthState:label=HEALTH)" 2>/dev/null || true

  printf "\nDelete a primary VM in another terminal and watch ACTION / STATUS / HEALTH change here.\n"
'