#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# 01 - SHOW BASELINE MIG INVENTORY
#
# Purpose:
#   Display the current primary and disaster-recovery Managed Instance Group
#   members before any failure is injected. This establishes the baseline for
#   the HA/DR demonstration.
#
# What to point out during the demo:
#   - Primary instances are spread across zones in us-east4.
#   - DR has warm capacity in us-central1.
#   - STATUS, ACTION, and HEALTH provide the starting state for later scripts.
# =============================================================================

# -----------------------------------------------------------------------------
# SECTION 1 - Demo resource names and regions
#
# Defaults match the Terraform deployment. Export any of these variables first
# if the names or regions are changed for another environment.
# -----------------------------------------------------------------------------
PROJECT_ID="${PROJECT_ID:-medicare-demo-260907-4f00}"
PRIMARY_REGION="${PRIMARY_REGION:-us-east4}"
DR_REGION="${DR_REGION:-us-central1}"
PRIMARY_MIG="${PRIMARY_MIG:-medicare-sp-portal-primary}"
DR_MIG="${DR_MIG:-medicare-sp-portal-dr}"

# -----------------------------------------------------------------------------
# SECTION 2 - Print a simple demo header
# -----------------------------------------------------------------------------
echo "============================================================"
echo " Medicare HA/DR - Managed Instance Groups (MIGs)"
echo " Project: $PROJECT_ID"
echo "============================================================"

# -----------------------------------------------------------------------------
# SECTION 3 - Show primary-region VM members
#
# list-instances shows which VMs the regional MIG currently manages, their
# zones, runtime state, any MIG action in progress, and health-check state.
# -----------------------------------------------------------------------------
echo
echo "PRIMARY MIG - $PRIMARY_REGION"
gcloud compute instance-groups managed list-instances "$PRIMARY_MIG" \
  --region="$PRIMARY_REGION" \
  --project="$PROJECT_ID" \
  --format="table(instance.basename():label=INSTANCE,instance.scope(zone):label=ZONE,instanceStatus:label=STATUS,currentAction:label=ACTION,healthState:label=HEALTH)"

# -----------------------------------------------------------------------------
# SECTION 4 - Show warm DR-region VM members
#
# This is the same view for the DR MIG. In the normal baseline, DR should have
# its warm minimum capacity available before the primary application is failed.
# -----------------------------------------------------------------------------
echo
echo "DR MIG - $DR_REGION"
gcloud compute instance-groups managed list-instances "$DR_MIG" \
  --region="$DR_REGION" \
  --project="$PROJECT_ID" \
  --format="table(instance.basename():label=INSTANCE,instance.scope(zone):label=ZONE,instanceStatus:label=STATUS,currentAction:label=ACTION,healthState:label=HEALTH)"

# -----------------------------------------------------------------------------
# SECTION 5 - Explain what the two MIGs represent
#
# This is the presentation takeaway: the primary regional MIG provides zonal
# resilience, while the second regional MIG provides pre-created DR capacity.
# -----------------------------------------------------------------------------
echo
echo "MIG = Managed Instance Group"
echo "Primary provides zonal HA. DR provides warm cross-region capacity."
