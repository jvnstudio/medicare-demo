#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# 04 - FAIL THE PRIMARY APPLICATION
#
# Purpose:
#   Simulate a primary-region APPLICATION failure without deleting or stopping
#   the Compute Engine VMs. The script stops nginx on every primary MIG VM.
#
# Expected behavior:
#   - Primary VMs remain RUNNING.
#   - The global load balancer health checks fail for the primary application.
#   - The same global endpoint continues serving from the healthy DR backend.
#
# Important interview wording:
#   This demonstrates regional application continuity. It does not simulate a
#   literal outage of the entire Google Cloud us-east4 region.
#
# Keep 02-watch-migs.sh running in another terminal while this script executes.
# =============================================================================

# -----------------------------------------------------------------------------
# MANUAL GCP CONSOLE EQUIVALENT
#
# Console
# Compute Engine -> VM instances
#         ↓
# SSH primary VM #1 -> stop nginx
# SSH primary VM #2 -> stop nginx
#         ↓
# Load Balancing -> Backend health
#         ↓
# us-east4 becomes UNHEALTHY
# us-central1 remains HEALTHY
#         ↓
# Open same global IP
#         ↓
# Page served from us-central1
#
# This script automates the SSH + "sudo systemctl stop nginx" steps above.
# It uses IAP SSH instead of requiring direct SSH to a VM public address.
# Prerequisite: tcp:22 from the IAP range 35.235.240.0/20 must be permitted.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# SECTION 1 - Primary environment and SSH retry settings
#
# WAIT_ATTEMPTS and WAIT_SECONDS control how long the script waits for a VM to
# settle after any recent MIG recreation before trying to connect through IAP.
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
# A MIG replacement can reuse a logical workload role while creating a new VM
# identity and SSH host key. This helper removes only the cached entry for the
# current Compute Engine instance ID. Strict host-key checking remains enabled
# when gcloud establishes the next IAP SSH connection.
# -----------------------------------------------------------------------------
refresh_compute_host_key() {
  local vm="$1"
  local zone="$2"
  local instance_id

  # Read the immutable numeric Compute Engine instance ID for the current VM.
  instance_id="$(
    gcloud compute instances describe "$vm" \
      --zone="$zone" \
      --project="$PROJECT_ID" \
      --format='value(id)' 2>/dev/null || true
  )"

  # Remove the matching cached host-key line only when it exists.
  if [[ -n "$instance_id" && -f "$KNOWN_HOSTS_FILE" ]] && \
     ssh-keygen -F "compute.${instance_id}" -f "$KNOWN_HOSTS_FILE" >/dev/null 2>&1; then
    echo "Refreshing cached SSH host key for $vm..."
    ssh-keygen -f "$KNOWN_HOSTS_FILE" -R "compute.${instance_id}" >/dev/null 2>&1 || true
  fi
}

# -----------------------------------------------------------------------------
# SECTION 3 - Wait until a VM is actually RUNNING
#
# Script 03 may have just caused the MIG to recreate a VM. Before SSH, this
# helper polls the exact instance until Compute Engine reports RUNNING or the
# configured retry window expires.
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
# SECTION 4 - Discover every current primary MIG VM and its exact zone
#
# The zone is parsed directly from the MIG instance URL. This avoids a race
# where an instance could be recreated between a separate name lookup and zone
# lookup. STATUS/ACTION are also captured for diagnostic context.
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
          ($u | try capture("/zones/(?<z>[^/]+)/instances/").z catch ""),
          (.instanceStatus // "-"),
          (.currentAction // "-")
        ]
      | @tsv
    '
)

# Stop if there is no primary capacity to fail.
if [[ ${#ROWS[@]} -eq 0 ]]; then
  echo "ERROR: No primary MIG instances found." >&2
  exit 1
fi

# -----------------------------------------------------------------------------
# SECTION 5 - Validate zones and wait for all primary VMs to be ready
#
# We do this before presenting the FAILOVER prompt so the operator knows all
# intended targets are currently resolvable and RUNNING.
# -----------------------------------------------------------------------------
for row in "${ROWS[@]}"; do
  IFS=$'\t' read -r VM ZONE STATUS ACTION <<<"$row"
  if [[ -z "$ZONE" ]]; then
    echo "ERROR: Could not derive zone from MIG instance URL for $VM." >&2
    exit 1
  fi
  wait_for_running "$VM" "$ZONE"
done

# -----------------------------------------------------------------------------
# SECTION 6 - Show the failure-injection plan
#
# The VMs are listed before any service is stopped so the presenter can explain
# exactly which primary application instances will be made unhealthy.
# -----------------------------------------------------------------------------
echo "============================================================"
echo " Medicare DR Demo - Fail Primary Application"
echo " MIG:    $PRIMARY_MIG"
echo " Region: $PRIMARY_REGION"
echo " SSH:    IAP tunnel"
echo "============================================================"
echo
echo "This stops nginx on ALL primary VMs while leaving the VMs running."
echo "The global load balancer should mark the primary backend unhealthy"
echo "and continue serving from the warm DR region."
echo
printf '%-30s %-15s\n' "INSTANCE" "ZONE"
printf '%-30s %-15s\n' "--------" "----"
for row in "${ROWS[@]}"; do
  IFS=$'\t' read -r VM ZONE STATUS ACTION <<<"$row"
  printf '%-30s %-15s\n' "$VM" "$ZONE"
done

echo

# -----------------------------------------------------------------------------
# SECTION 7 - Manual application-failure approval
#
# The script will not stop nginx unless the operator types FAILOVER exactly.
# -----------------------------------------------------------------------------
read -r -p "Type FAILOVER to stop nginx on all primary VMs: " CONFIRM
if [[ "$CONFIRM" != "FAILOVER" ]]; then
  echo "Cancelled."
  exit 0
fi

# -----------------------------------------------------------------------------
# SECTION 8 - Stop nginx on every primary VM through IAP
#
# Each VM is rechecked immediately before SSH. The VMs remain powered on; only
# the application service is stopped. Health checks should therefore show the
# distinction between VM RUNNING state and application/LB UNHEALTHY state.
# -----------------------------------------------------------------------------
for row in "${ROWS[@]}"; do
  IFS=$'\t' read -r VM ZONE STATUS ACTION <<<"$row"

  echo
  wait_for_running "$VM" "$ZONE"
  refresh_compute_host_key "$VM" "$ZONE"
  echo "Stopping nginx on $VM ($ZONE) through IAP..."
  gcloud compute ssh "$VM" \
    --zone="$ZONE" \
    --project="$PROJECT_ID" \
    --tunnel-through-iap \
    --command="sudo systemctl stop nginx"
done

# -----------------------------------------------------------------------------
# SECTION 9 - Tell the presenter what to watch
#
# In 02-watch-migs.sh, primary VM STATUS should stay RUNNING while LB HEALTH
# becomes unhealthy. DR should remain healthy and serve the same global IP.
# -----------------------------------------------------------------------------
echo
echo "Primary application failure injected."
echo "Keep 02-watch-migs.sh running and watch LB HEALTH change while DR stays healthy."
