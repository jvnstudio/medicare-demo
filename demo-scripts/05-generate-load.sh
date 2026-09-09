#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# 05 - GENERATE LOAD AGAINST THE GLOBAL ENDPOINT
#
# Purpose:
#   Generate sustained HTTP requests against the Medicare demo's global load
#   balancer so the DR autoscaler has enough load to recommend/add capacity.
#
# Expected demo behavior:
#   After script 04 makes the primary application unhealthy, this traffic is
#   served by the DR backend. In 02-watch-migs.sh, watch DR Recommended and MIG
#   target size move from the warm minimum toward the configured maximum.
#
# Defaults:
#   30 parallel workers for 120 seconds. Override with environment variables,
#   for example: WORKERS=50 DURATION=180 ./05-generate-load.sh
# =============================================================================

# -----------------------------------------------------------------------------
# SECTION 1 - Load-test settings
#
# LB_ADDRESS_NAME is the reserved global IP resource created by Terraform.
# WORKERS controls concurrency and DURATION controls how long each worker runs.
# -----------------------------------------------------------------------------
PROJECT_ID="${PROJECT_ID:-medicare-demo-260907-4f00}"
LB_ADDRESS_NAME="${LB_ADDRESS_NAME:-medicare-sp-global-ip}"
WORKERS="${WORKERS:-30}"
DURATION="${DURATION:-120}"

# -----------------------------------------------------------------------------
# SECTION 2 - Resolve the current global load-balancer IP
#
# The script deliberately sends traffic to the same public endpoint users see;
# it does not target a primary or DR VM directly.
# -----------------------------------------------------------------------------
LB_IP="$(gcloud compute addresses describe "$LB_ADDRESS_NAME" \
  --global \
  --project="$PROJECT_ID" \
  --format='value(address)')"

# -----------------------------------------------------------------------------
# SECTION 3 - Show the test parameters before traffic starts
# -----------------------------------------------------------------------------
echo "============================================================"
echo " Medicare HA/DR - Generate Load"
echo " Global IP: $LB_IP"
echo " Workers:   $WORKERS"
echo " Duration:  ${DURATION}s"
echo "============================================================"
echo
echo "Generating HTTP traffic. Keep 02-watch-migs.sh running and watch DR target/recommended size grow."

# -----------------------------------------------------------------------------
# SECTION 4 - Start parallel HTTP workers
#
# Each background subshell repeatedly curls the global endpoint until its local
# timer expires. Individual HTTP failures are ignored because temporary errors
# during failover/scaling are part of what the live dashboard is observing.
# -----------------------------------------------------------------------------
for ((i=1; i<=WORKERS; i++)); do
  (
    end=$((SECONDS + DURATION))
    while (( SECONDS < end )); do
      curl -fsS --max-time 3 "http://${LB_IP}/" >/dev/null 2>&1 || true
    done
  ) &
done

# -----------------------------------------------------------------------------
# SECTION 5 - Wait for every load worker to finish
#
# The script stays in the foreground until all background request loops end.
# -----------------------------------------------------------------------------
wait

echo "Load generation complete."
