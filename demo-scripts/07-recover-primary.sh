#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-medicare-demo-260907-4f00}"
PRIMARY_REGION="${PRIMARY_REGION:-us-east4}"
PRIMARY_MIG="${PRIMARY_MIG:-medicare-sp-portal-primary}"

mapfile -t ROWS < <(gcloud compute instance-groups managed list-instances "$PRIMARY_MIG" \
  --region="$PRIMARY_REGION" \
  --project="$PROJECT_ID" \
  --format="csv[no-heading](instance.basename(),instance.scope(zone))")

if [[ ${#ROWS[@]} -eq 0 ]]; then
  echo "No primary MIG instances found."
  exit 1
fi

echo "============================================================"
echo " Medicare HA/DR - Recover Primary Application"
echo " Starts nginx on all currently managed primary VMs."
echo " Use this as a deterministic reset between live demos."
echo "============================================================"

for row in "${ROWS[@]}"; do
  VM="${row%%,*}"
  ZONE="${row#*,}"
  echo "Starting nginx on $VM ($ZONE)..."
  gcloud compute ssh "$VM" \
    --zone="$ZONE" \
    --project="$PROJECT_ID" \
    --command="sudo systemctl start nginx"
done

echo
echo "Primary application recovery requested."
echo "Allow health checks a short time to mark the primary backend healthy again."
