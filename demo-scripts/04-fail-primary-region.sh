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

ROWS=()
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

  ROWS+=("$VM|$ZONE")
done

echo "============================================================"
echo " Medicare DR Demo - Fail Primary Application"
echo " MIG:    $PRIMARY_MIG"
echo " Region: $PRIMARY_REGION"
echo "============================================================"
echo
echo "This stops nginx on ALL primary VMs while leaving the VMs running."
echo "The global load balancer should mark the primary backend unhealthy"
echo "and continue serving from the warm DR region."
echo
printf '%-30s %-15s\n' "INSTANCE" "ZONE"
printf '%-30s %-15s\n' "--------" "----"
for row in "${ROWS[@]}"; do
  VM="${row%%|*}"
  ZONE="${row#*|}"
  printf '%-30s %-15s\n' "$VM" "$ZONE"
done

echo
read -r -p "Type FAILOVER to stop nginx on all primary VMs: " CONFIRM
if [[ "$CONFIRM" != "FAILOVER" ]]; then
  echo "Cancelled."
  exit 0
fi

for row in "${ROWS[@]}"; do
  VM="${row%%|*}"
  ZONE="${row#*|}"

  echo
  echo "Stopping nginx on $VM ($ZONE)..."
  gcloud compute ssh "$VM" \
    --zone="$ZONE" \
    --project="$PROJECT_ID" \
    --command="sudo systemctl stop nginx"
done

echo
echo "Primary application failure injected."
echo "Keep 02-watch-migs.sh running and watch LB HEALTH change while DR stays healthy."
