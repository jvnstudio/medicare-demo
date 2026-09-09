#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# 03 - DELETE ONE PRIMARY VM
#
# Purpose:
#   Simulate the loss of one VM in the primary regional Managed Instance Group.
#   The VM is intentionally deleted and the MIG should create a replacement to
#   restore its configured desired capacity.
#
# What this proves:
#   MIG desired-capacity reconciliation and zonal VM resilience.
#
# What this does NOT prove:
#   This is not the health-check autohealing test. We explicitly delete a VM,
#   so the MIG is reacting to missing desired capacity rather than repairing an
#   unhealthy but still-existing VM.
#
# Demo tip:
#   Keep 02-watch-migs.sh running in another terminal while this script runs.
# =============================================================================

# -----------------------------------------------------------------------------
# SECTION 1 - Primary MIG configuration
# -----------------------------------------------------------------------------
PROJECT_ID="${PROJECT_ID:-medicare-demo-260907-4f00}"
PRIMARY_REGION="${PRIMARY_REGION:-us-east4}"
PRIMARY_MIG="${PRIMARY_MIG:-medicare-sp-portal-primary}"

# -----------------------------------------------------------------------------
# SECTION 2 - Select the VM to delete
#
# For repeatability, VM_NAME and VM_ZONE can be supplied explicitly. Otherwise
# the script chooses the first VM currently managed by the primary MIG.
# -----------------------------------------------------------------------------
if [[ -n "${VM_NAME:-}" && -n "${VM_ZONE:-}" ]]; then
  TARGET_VM="$VM_NAME"
  TARGET_ZONE="$VM_ZONE"
else
  # Ask the regional MIG for one managed VM name.
  # Do not trust a separate scope field for zone parsing because gcloud output
  # formatting can vary between command versions.
  TARGET_VM="$(gcloud compute instance-groups managed list-instances "$PRIMARY_MIG" \
    --region="$PRIMARY_REGION" \
    --project="$PROJECT_ID" \
    --format=json \
    | jq -r '.[0].instance // empty | split("/")[-1]')"

  # Stop if the primary MIG currently has no VM to demonstrate with.
  if [[ -z "$TARGET_VM" || "$TARGET_VM" == "null" ]]; then
    echo "ERROR: No instances found in primary MIG $PRIMARY_MIG." >&2
    exit 1
  fi

  # Resolve the VM's zone from its actual Compute Engine instance record. This
  # avoids deleting with a guessed zone when MIG activity is in progress.
  TARGET_ZONE="$(gcloud compute instances list \
    --project="$PROJECT_ID" \
    --filter="name=$TARGET_VM" \
    --format=json \
    | jq -r '.[0].zone // empty | split("/")[-1]')"

  # If the zone cannot be resolved, print the matching VM records and stop.
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

# -----------------------------------------------------------------------------
# SECTION 3 - Validate the zone before a destructive action
#
# A valid GCP zone looks like us-east4-a or us-central1-b. Refusing unexpected
# values reduces the chance of issuing the delete command with bad input.
# -----------------------------------------------------------------------------
if [[ ! "$TARGET_ZONE" =~ ^[a-z]+-[a-z]+[0-9]+-[a-z]$ ]]; then
  echo "ERROR: Refusing to delete because '$TARGET_ZONE' does not look like a GCP zone." >&2
  exit 1
fi

# -----------------------------------------------------------------------------
# SECTION 4 - Show exactly what will be deleted
#
# This gives the presenter one last visual confirmation of the MIG, instance,
# and zone before the manual approval prompt.
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# SECTION 5 - Manual destructive-action approval
#
# The VM is not deleted unless the operator types the exact word DELETE.
# -----------------------------------------------------------------------------
read -r -p "Type DELETE to remove this VM: " CONFIRM
if [[ "$CONFIRM" != "DELETE" ]]; then
  echo "Cancelled."
  exit 0
fi

# -----------------------------------------------------------------------------
# SECTION 6 - Delete the selected VM
#
# The instance disappears from Compute Engine. Because it belongs to a regional
# MIG with a configured target size, the MIG should immediately begin creating
# a replacement instance to restore desired capacity.
# -----------------------------------------------------------------------------
gcloud compute instances delete "$TARGET_VM" \
  --zone="$TARGET_ZONE" \
  --project="$PROJECT_ID" \
  --quiet

# -----------------------------------------------------------------------------
# SECTION 7 - Tell the presenter what to watch next
#
# In 02-watch-migs.sh, look for MIG ACTION changing to CREATING/RECREATING and
# then returning to a stable, healthy instance count.
# -----------------------------------------------------------------------------
echo
echo "Deleted $TARGET_VM. The MIG should automatically restore desired capacity."
