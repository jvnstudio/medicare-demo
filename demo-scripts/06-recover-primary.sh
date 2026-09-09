#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# 06 - RECOVER THE PRIMARY APPLICATION
#
# Purpose:
#   Reverse the application failure injected by script 04 by starting nginx on
#   every current primary MIG VM through an IAP SSH tunnel.
#
# Expected behavior:
#   - Primary VMs were already RUNNING; nginx is started again.
#   - Load-balancer health checks begin succeeding in us-east4.
#   - 02-watch-migs.sh shows primary LB HEALTH returning to HEALTHY.
#
# This is controlled service restoration. It demonstrates recovery mechanics,
# not a guarantee of an application-level production RTO by itself.
# =============================================================================

# -----------------------------------------------------------------------------
# SECTION 1 - Primary environment and SSH retry settings
#
# These values identify the primary regional MIG and define how long the script
# waits for any recent MIG activity to settle before connecting through IAP.
# -----------------------------------------------------------------------------
PROJECT_ID="${PROJECT_ID:-medicare-demo-260907-4f00}"
PRIMARY_REGION="${PRIMARY_REGION:-us-east4}"
PRIMARY_MIG="${PRIMARY_MIG:-medicare-sp-portal-primary}"
KNOWN_HOSTS_FILE="${HOME}/.ssh/google_compute_known_hosts"
WAIT_ATTEMPTS="${WAIT_ATTEMPTS:-36}"
WAIT_SECONDS="${WAIT_SECONDS:-5}"

# -----------------------------------------------------------------------------
# SECTION 2 - Refresh only the current VM's cached Compute Engine SSH host key
#
# A MIG recreation can create a VM with a new Compute Engine instance ID and
# host key. Remove only the matching cached entry before reconnecting. Strict
# host-key checking remains enabled for the new IAP SSH connection.
# -----------------------------------------------------------------------------
refresh_compute_host_key() {
  local vm="$1"
  local zone="$2"
  local instance_id

  # Look up the current immutable numeric ID for this exact VM.
  instance_id="$(
    gcloud compute instances describe "$vm" \
      --zone="$zone" \
      --project="$PROJECT_ID" \
      --format='value(id)' 2>/dev/null || true
  )"

  # Remove the cached key only if a matching Compute Engine entry exists.
  if [[ -n "$instance_id" && -f "$KNOWN_HOSTS_FILE" ]] && \
     ssh-keygen -F "compute.${instance_id}" -f "$KNOWN_HOSTS_FILE" >/dev/null 2>&1; then
    echo "Refreshing cached SSH host key for $vm..."
    ssh-keygen -f "$KNOWN_HOSTS_FILE" -R "compute.${instance_id}" >/dev/null 2>&1 || true
  fi
}

# -----------------------------------------------------------------------------
# SECTION 3 - Wait until a target VM is RUNNING
#
# If script 03 caused a recent replacement, the MIG may still be finishing VM
# creation. Poll the exact instance before attempting the recovery SSH command.
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# SECTION 4 - Discover every current primary VM and exact zone
#
# Read the current membership from the regional MIG rather than assuming the VM
# names from script 04 still exist. This matters because the MIG may have
# recreated an instance during the demonstration.
# -----------------------------------------------------------------------------
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

# Stop if there are no current primary instances to recover.
if [[ ${#ROWS[@]} -eq 0 ]]; then
  echo "ERROR: No primary MIG instances found." >&2
  exit 1
fi

# -----------------------------------------------------------------------------
# SECTION 5 - Show the recovery target
# -----------------------------------------------------------------------------
echo "============================================================"
echo " Medicare HA/DR - Recover Primary Application"
echo " MIG:    $PRIMARY_MIG"
echo " Region: $PRIMARY_REGION"
echo " SSH:    IAP tunnel"
echo "============================================================"

# -----------------------------------------------------------------------------
# SECTION 6 - Start nginx on every current primary VM through IAP
#
# For each VM, validate its zone, wait until it is RUNNING, refresh only its
# cached host-key entry if needed, then start the application service.
# -----------------------------------------------------------------------------
for row in "${ROWS[@]}"; do
  IFS=$'\t' read -r VM ZONE <<<"$row"

  # The zone must come from the MIG instance URL. Do not continue with an empty
  # zone because gcloud SSH needs the exact zonal instance identity.
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

# -----------------------------------------------------------------------------
# SECTION 7 - Tell the presenter what to watch next
#
# Health checks are not instantaneous. Keep the dashboard running until the
# primary backend returns to HEALTHY and the recovery state is visible.
# -----------------------------------------------------------------------------
echo
echo "Primary application recovery requested."
echo "Keep 02-watch-migs.sh running until LB HEALTH returns to HEALTHY."
