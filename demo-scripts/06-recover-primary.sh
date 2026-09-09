#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-medicare-demo-260907-4f00}"
PRIMARY_REGION="${PRIMARY_REGION:-us-east4}"
PRIMARY_MIG="${PRIMARY_MIG:-medicare-sp-portal-primary}"

mapfile -t VMS < <(
  gcloud compute instance-groups managed list-instances "$PRIMARY_MIG" \
    --region="$PRIMARY_REGION" \
    --project="$PROJECT_ID" \
    --format=json \
  | jq -r '.[] | (.instance // "") | split("/")[-1] | select(length > 0)'
)

if [[ ${#VMS[@]} -eq 0 ]]; then
  echo "ERROR: No primary MIG instances found." >&2
  exit 1
fi

echo "============================================================"
echo " Medicare HA/DR - Recover Primary Application"
echo " MIG:    $PRIMARY_MIG"
echo " Region: $PRIMARY_REGION"
echo " SSH:    IAP tunnel"
echo "============================================================"

for VM in "${VMS[@]}"; do
  ZONE="$(
    gcloud compute instances list \
      --project="$PROJECT_ID" \
      --filter="name=$VM" \
      --format=json \
    | jq -r '.[0].zone // empty | split("/")[-1]'
  )"

  if [[ -z "$ZONE" ]]; then
    echo "ERROR: Could not resolve zone for $VM." >&2
    exit 1
  fi

  echo "Starting nginx on $VM ($ZONE) through IAP..."
  gcloud compute ssh "$VM" \
    --zone="$ZONE" \
    --project="$PROJECT_ID" \
    --tunnel-through-iap \
    --command="sudo systemctl start nginx"
done

echo
echo "Primary application recovery requested."
echo "Keep 02-watch-migs.sh running until LB HEALTH returns to HEALTHY."
