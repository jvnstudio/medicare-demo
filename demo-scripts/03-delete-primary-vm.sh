#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-medicare-demo-260907-4f00}"
PRIMARY_REGION="${PRIMARY_REGION:-us-east4}"
PRIMARY_MIG="${PRIMARY_MIG:-medicare-sp-portal-primary}"

if [[ -n "${VM_NAME:-}" && -n "${VM_ZONE:-}" ]]; then
  TARGET_VM="$VM_NAME"
  TARGET_ZONE="$VM_ZONE"
else
  # Get one managed VM name from the MIG. Do not trust the MIG scope field for
  # zone parsing because gcloud output formatting can differ by command/version.
  TARGET_VM="$(gcloud compute instance-groups managed list-instances "$PRIMARY_MIG" \
    --region="$PRIMARY_REGION" \
    --project="$PROJECT_ID" \
    --format=json \
    | jq -r '.[0].instance // empty | split("/")[-1]')"

  if [[ -z "$TARGET_VM" || "$TARGET_VM" == "null" ]]; then
    echo "ERROR: No instances found in primary MIG $PRIMARY_MIG." >&2
    exit 1
  fi

  # Resolve the zone independently from the actual Compute Engine VM record.
  TARGET_ZONE="$(gcloud compute instances list \
    --project="$PROJECT_ID" \
    --filter="name=$TARGET_VM" \
    --format=json \
    | jq -r '.[0].zone // empty | split("/")[-1]')"

  if [[ -z "$TARGET_ZONE" || "$TARGET_ZONE" == "null" ]]; then
    echo "ERROR: Could not resolve a zone for VM $TARGET_VM." >&2
    echo "Current matching instances:" >&2
    gcloud compute instances list \
      --project="$PROJECT_ID" \
      --filter="name=$TARGET_VM" \
      --format="table(name,zone,status)" >&2 || true
    exit 1
  fi
fi

# Safety check: a real zone should look like us-east4-a, us-central1-b, etc.
if [[ ! "$TARGET_ZONE" =~ ^[a-z]+-[a-z]+[0-9]+-[a-z]$ ]]; then
  echo "ERROR: Refusing to delete because '$TARGET_ZONE' does not look like a GCP zone." >&2
  exit 1
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
