#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-medicare-demo-260907-4f00}"
PRIMARY_REGION="${PRIMARY_REGION:-us-east4}"
PRIMARY_MIG="${PRIMARY_MIG:-medicare-sp-portal-primary}"

if [[ -n "${VM_NAME:-}" && -n "${VM_ZONE:-}" ]]; then
  TARGET_VM="$VM_NAME"
  TARGET_ZONE="$VM_ZONE"
else
  TARGET_ROW="$(gcloud compute instance-groups managed list-instances "$PRIMARY_MIG" \
    --region="$PRIMARY_REGION" \
    --project="$PROJECT_ID" \
    --format="csv[no-heading](instance.basename(),instance.scope(zone))" \
    | head -n1)"

  if [[ -z "$TARGET_ROW" ]]; then
    echo "No instances found in primary MIG $PRIMARY_MIG."
    exit 1
  fi

  TARGET_VM="${TARGET_ROW%%,*}"
  TARGET_ZONE="${TARGET_ROW#*,}"
fi

echo "============================================================"
echo " Medicare HA Demo - Delete One Primary VM"
echo " MIG:      $PRIMARY_MIG"
echo " Instance: $TARGET_VM"
echo " Zone:     $TARGET_ZONE"
echo "============================================================"
echo
echo "This demonstrates MIG desired-capacity reconciliation."
echo "Keep 02-watch-migs.sh running in another terminal."
echo
read -r -p "Type DELETE to remove this VM: " CONFIRM
if [[ "$CONFIRM" != "DELETE" ]]; then
  echo "Cancelled."
  exit 0
fi

gcloud compute instances delete "$TARGET_VM" \
  --zone="$TARGET_ZONE" \
  --project="$PROJECT_ID" \
  --quiet

echo
echo "Deleted $TARGET_VM. The MIG should automatically restore desired capacity."
