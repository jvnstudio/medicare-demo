#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-medicare-demo-260907-4f00}"
PRIMARY_REGION="${PRIMARY_REGION:-us-east4}"
DR_REGION="${DR_REGION:-us-central1}"
PRIMARY_MIG="${PRIMARY_MIG:-medicare-sp-portal-primary}"
DR_MIG="${DR_MIG:-medicare-sp-portal-dr}"

echo "============================================================"
echo " Medicare HA/DR - Managed Instance Groups (MIGs)"
echo " Project: $PROJECT_ID"
echo "============================================================"

echo
echo "PRIMARY MIG - $PRIMARY_REGION"
gcloud compute instance-groups managed list-instances "$PRIMARY_MIG" \
  --region="$PRIMARY_REGION" \
  --project="$PROJECT_ID" \
  --format="table(instance.basename():label=INSTANCE,instance.scope(zone):label=ZONE,instanceStatus:label=STATUS,currentAction:label=ACTION,healthState:label=HEALTH)"

echo
echo "DR MIG - $DR_REGION"
gcloud compute instance-groups managed list-instances "$DR_MIG" \
  --region="$DR_REGION" \
  --project="$PROJECT_ID" \
  --format="table(instance.basename():label=INSTANCE,instance.scope(zone):label=ZONE,instanceStatus:label=STATUS,currentAction:label=ACTION,healthState:label=HEALTH)"

echo
echo "MIG = Managed Instance Group"
echo "Primary provides zonal HA. DR provides warm cross-region capacity."
