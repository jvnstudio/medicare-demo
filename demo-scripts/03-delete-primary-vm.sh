#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-medicare-demo-260907-4f00}"
PRIMARY_REGION="${PRIMARY_REGION:-us-east4}"
PRIMARY_MIG="${PRIMARY_MIG:-medicare-sp-portal-primary}"

if [[ -n "${VM_NAME:-}" && -n "${VM_ZONE:-}" ]]; then
  TARGET_VM="$VM_NAME"
  TARGET_ZONE="$VM_ZONE"
else
  # Ask the MIG for one managed instance self-link. The self-link contains
  # both the zone and VM name, so we do not depend on gcloud scope() formatting.
  TARGET_URL="$(gcloud compute instance-groups managed list-instances "$PRIMARY_MIG" \
    --region="$PRIMARY_REGION" \
    --project="$PROJECT_ID" \
    --format="value(instance)" \
    | head -n1)"

  if [[ -z "$TARGET_URL" ]]; then
    echo "No instances found in primary MIG $PRIMARY_MIG."
    exit 1
  fi

  TARGET_VM="${TARGET_URL##*/}"
  TARGET_ZONE="$(sed -n 's#^.*/zones/\([^/]*\)/instances/.*#\1#p' <<<"$TARGET_URL")"

  if [[ -z "$TARGET_VM" || -z "$TARGET_ZONE" ]]; then
    echo "ERROR: Could not parse VM name/zone from MIG instance URL:" >&2
    echo "  $TARGET_URL" >&2
    exit 1
  fi
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
