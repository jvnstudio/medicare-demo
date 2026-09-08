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
echo " Medicare HA/DR - Simulate Primary Application Failure"
echo " This stops nginx on ALL primary MIG VMs."
echo " The VMs stay running; only the application health endpoint fails."
echo "============================================================"

echo
for row in "${ROWS[@]}"; do
  echo "  $row"
done

echo
read -r -p "Type FAILOVER to stop nginx on all primary VMs: " CONFIRM
if [[ "$CONFIRM" != "FAILOVER" ]]; then
  echo "Cancelled."
  exit 0
fi

for row in "${ROWS[@]}"; do
  VM="${row%%,*}"
  ZONE="${row#*,}"
  echo
  echo "Stopping nginx on $VM ($ZONE)..."
  gcloud compute ssh "$VM" \
    --zone="$ZONE" \
    --project="$PROJECT_ID" \
    --command="sudo systemctl stop nginx"
done

echo
echo "Primary application failure injected."
echo "Watch 02-watch-traffic.sh and 03-watch-health.sh in separate terminals."
