#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-medicare-demo-260907-4f00}"
PRIMARY_REGION="${PRIMARY_REGION:-us-east4}"
PRIMARY_MIG="${PRIMARY_MIG:-medicare-sp-portal-primary}"
KNOWN_HOSTS_FILE="${HOME}/.ssh/google_compute_known_hosts"
WAIT_ATTEMPTS="${WAIT_ATTEMPTS:-36}"
WAIT_SECONDS="${WAIT_SECONDS:-5}"

# MIG recreation can replace a VM's SSH host key. Remove only the cached
# Compute Engine host-key entry for the current VM ID before reconnecting.
# Strict host-key checking remains enabled for the new IAP SSH connection.
refresh_compute_host_key() {
  local vm="$1"
  local zone="$2"
  local instance_id

  instance_id="$(
    gcloud compute instances describe "$vm" \
      --zone="$zone" \
      --project="$PROJECT_ID" \
      --format='value(id)' 2>/dev/null || true
  )"

  if [[ -n "$instance_id" && -f "$KNOWN_HOSTS_FILE" ]] && \
     ssh-keygen -F "compute.${instance_id}" -f "$KNOWN_HOSTS_FILE" >/dev/null 2>&1; then
    echo "Refreshing cached SSH host key for $vm..."
    ssh-keygen -f "$KNOWN_HOSTS_FILE" -R "compute.${instance_id}" >/dev/null 2>&1 || true
  fi
}

wait_for_running() {
  local vm="$1"
  local zone="$2"
  local status=""

  for ((attempt=1; attempt<=WAIT_ATTEMPTS; attempt++)); do
    status="$(
      gcloud compute instances describe "$vm" \
        --zone="$zone" \
        --project="$PROJECT_ID" \
        --format='value(status)' 2>/dev/null || true
    )"

    if [[ "$status" == "RUNNING" ]]; then
      return 0
    fi

    if (( attempt == 1 )); then
      echo "Waiting for $vm ($zone) to be ready after MIG activity..."
    fi
    sleep "$WAIT_SECONDS"
  done

  echo "ERROR: $vm ($zone) did not reach RUNNING state in time." >&2
  return 1
}

mapfile -t ROWS < <(
  gcloud compute instance-groups managed list-instances "$PRIMARY_MIG" \
    --region="$PRIMARY_REGION" \
    --project="$PROJECT_ID" \
    --format=json \
  | jq -r '
      .[]?
      | (.instance // "") as $u
      | select($u | length > 0)
      | [
          ($u | split("/")[-1]),
          ($u | try capture("/zones/(?<z>[^/]+)/instances/").z catch "")
        ]
      | @tsv
    '
)

if [[ ${#ROWS[@]} -eq 0 ]]; then
  echo "ERROR: No primary MIG instances found." >&2
  exit 1
fi

echo "============================================================"
echo " Medicare HA/DR - Recover Primary Application"
echo " MIG:    $PRIMARY_MIG"
echo " Region: $PRIMARY_REGION"
echo " SSH:    IAP tunnel"
echo "============================================================"

for row in "${ROWS[@]}"; do
  IFS=$'\t' read -r VM ZONE <<<"$row"

  if [[ -z "$ZONE" ]]; then
    echo "ERROR: Could not derive zone from MIG instance URL for $VM." >&2
    exit 1
  fi

  wait_for_running "$VM" "$ZONE"
  refresh_compute_host_key "$VM" "$ZONE"
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
