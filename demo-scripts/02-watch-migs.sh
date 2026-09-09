#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# 02 - LIVE HA/DR DASHBOARD
#
# Purpose:
#   Continuously display VM state, MIG activity, MIG health, load-balancer
#   health, and DR autoscaling information in one fixed terminal dashboard.
#
# How to use it:
#   Start this script in a separate Cloud Shell terminal and leave it running
#   while executing scripts 03, 04, 05, and 06 in another terminal.
#
# What it proves visually:
#   - VM deletion/recreation and MIG desired-capacity reconciliation.
#   - Primary backend health changing during the application-failure test.
#   - DR remaining healthy and scaling as load increases.
#   - Primary health returning during recovery.
# =============================================================================

# -----------------------------------------------------------------------------
# SECTION 1 - Demo resources and dashboard refresh interval
#
# These defaults match the Terraform environment. INTERVAL controls how often
# the script refreshes the dashboard data.
# -----------------------------------------------------------------------------
PROJECT_ID="${PROJECT_ID:-medicare-demo-260907-4f00}"
PRIMARY_REGION="${PRIMARY_REGION:-us-east4}"
DR_REGION="${DR_REGION:-us-central1}"
PRIMARY_MIG="${PRIMARY_MIG:-medicare-sp-portal-primary}"
DR_MIG="${DR_MIG:-medicare-sp-portal-dr}"
DR_AUTOSCALER="${DR_AUTOSCALER:-medicare-sp-dr-autoscaler}"
BACKEND_SERVICE="${BACKEND_SERVICE:-medicare-sp-portal-backend}"
INTERVAL="${INTERVAL:-2}"

# -----------------------------------------------------------------------------
# SECTION 2 - Reserve fixed display slots
#
# Fixed slots keep the terminal rows from shifting while VMs are deleted,
# recreated, or added by the DR autoscaler.
# -----------------------------------------------------------------------------
PRIMARY_SLOTS="${PRIMARY_SLOTS:-4}"
DR_SLOTS="${DR_SLOTS:-4}"

# -----------------------------------------------------------------------------
# SECTION 3 - Define the common table layout
#
# One format string is used for both headers and instance rows so the dashboard
# stays aligned while values change.
# -----------------------------------------------------------------------------
ROW_FORMAT='%-28.28s %-13.13s %-10.10s %-12.12s %-10.10s %-10.10s'

# -----------------------------------------------------------------------------
# SECTION 4 - Terminal rendering helpers
#
# write_line rewrites one fixed terminal row in place. format_header creates
# the column names using the exact same spacing as the instance data rows.
# -----------------------------------------------------------------------------
write_line() {
  local row="$1"
  shift
  printf '\033[%s;1H\033[2K%s' "$row" "$*"
}

format_header() {
  printf "$ROW_FORMAT" "INSTANCE" "ZONE" "VM STATUS" "MIG ACTION" "MIG HEALTH" "LB HEALTH"
}

# -----------------------------------------------------------------------------
# SECTION 5 - Read current VM/MIG state
#
# The function asks the regional MIG for its managed instances and returns a
# tab-separated row containing instance, zone, VM status, current MIG action,
# and MIG health state. jq normalizes the gcloud JSON output.
# -----------------------------------------------------------------------------
fetch_mig_rows() {
  local mig="$1"
  local region="$2"

  gcloud compute instance-groups managed list-instances "$mig" \
    --region="$region" \
    --project="$PROJECT_ID" \
    --format=json 2>/dev/null \
  | jq -r '
      .[]?
      | [
          ((.instance // "") | split("/")[-1]),
          ((.instance // "") | try capture("/zones/(?<z>[^/]+)/instances/").z catch "-"),
          (.instanceStatus // "-"),
          (.currentAction // "-"),
          (.healthState // "-")
        ]
      | @tsv
    ' 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# SECTION 6 - Read global load-balancer backend health
#
# The load balancer evaluates backend instances independently of the MIG. This
# lets the dashboard show when a VM can still be RUNNING but the application
# endpoint has become UNHEALTHY.
# -----------------------------------------------------------------------------
fetch_lb_rows() {
  gcloud compute backend-services get-health "$BACKEND_SERVICE" \
    --global \
    --project="$PROJECT_ID" \
    --format=json 2>/dev/null \
  | jq -r '
      .[]?
      | .status.healthStatus[]?
      | [
          ((.instance // "") | split("/")[-1]),
          (.healthState // "UNKNOWN")
        ]
      | @tsv
    ' 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# SECTION 7 - Read DR MIG capacity metadata
#
# targetSize is the number of DR VMs the MIG is currently trying to maintain.
# isStable tells us whether the MIG has finished its current resize/recreate
# work.
# -----------------------------------------------------------------------------
fetch_dr_mig_meta() {
  gcloud compute instance-groups managed describe "$DR_MIG" \
    --region="$DR_REGION" \
    --project="$PROJECT_ID" \
    --format=json 2>/dev/null \
  | jq -r '[((.targetSize // "-")|tostring), ((.status.isStable // false)|tostring)] | @tsv' \
  2>/dev/null || true
}

# -----------------------------------------------------------------------------
# SECTION 8 - Read DR autoscaler recommendations
#
# recommendedSize is especially useful during script 05 because it shows the
# autoscaler's desired capacity before or while the MIG is resizing.
# -----------------------------------------------------------------------------
fetch_dr_autoscaler_meta() {
  gcloud compute autoscalers describe "$DR_AUTOSCALER" \
    --region="$DR_REGION" \
    --project="$PROJECT_ID" \
    --format=json 2>/dev/null \
  | jq -r '[
      (.status // "-"),
      ((.recommendedSize // "-")|tostring),
      ((.autoscalingPolicy.minNumReplicas // "-")|tostring),
      ((.autoscalingPolicy.maxNumReplicas // "-")|tostring)
    ] | @tsv' \
  2>/dev/null || true
}

# -----------------------------------------------------------------------------
# SECTION 9 - Combine MIG state with load-balancer health
#
# Each displayed row begins with the MIG data. The function then looks up the
# same instance in the associative array populated from load-balancer health.
# Blank dashboard slots are printed as dashes so the screen does not shift.
# -----------------------------------------------------------------------------
format_instance_row() {
  local raw="$1"

  if [[ -z "$raw" ]]; then
    printf "$ROW_FORMAT" "-" "-" "-" "-" "-" "-"
    return
  fi

  local instance zone status action mig_health lb
  IFS=$'\t' read -r instance zone status action mig_health <<<"$raw"

  lb="-"
  if [[ -n "${lb_health[$instance]+x}" ]]; then
    lb="${lb_health[$instance]}"
  fi

  printf "$ROW_FORMAT" \
    "${instance:--}" \
    "${zone:--}" \
    "${status:--}" \
    "${action:--}" \
    "${mig_health:--}" \
    "${lb:--}"
}

# -----------------------------------------------------------------------------
# SECTION 10 - Restore the terminal when the watcher exits
#
# The dashboard hides the cursor while running. cleanup makes sure the cursor
# is visible again when Ctrl-C, EXIT, or TERM stops the script.
# -----------------------------------------------------------------------------
cleanup() {
  printf '\033[?25h\033[25;1H\n'
}
trap cleanup EXIT INT TERM

# Clear the terminal once. Later updates overwrite fixed rows in place instead
# of clearing the entire screen, which reduces flicker during the presentation.
printf '\033[2J\033[H\033[?25l'

declare -A lb_health

# -----------------------------------------------------------------------------
# SECTION 11 - Main monitoring loop
#
# Every iteration gathers all state first and only then updates the visible
# dashboard. This keeps one screen refresh internally consistent.
# -----------------------------------------------------------------------------
while true; do
  # Fetch current primary/DR instance state, LB health, and autoscaler metadata.
  mapfile -t primary_rows < <(fetch_mig_rows "$PRIMARY_MIG" "$PRIMARY_REGION")
  mapfile -t dr_rows < <(fetch_mig_rows "$DR_MIG" "$DR_REGION")
  mapfile -t current_lb_rows < <(fetch_lb_rows)
  dr_mig_meta="$(fetch_dr_mig_meta)"
  dr_autoscaler_meta="$(fetch_dr_autoscaler_meta)"

  # Build an instance-name -> LB-health lookup table for the formatted rows.
  lb_health=()
  for raw in "${current_lb_rows[@]:-}"; do
    [[ -z "$raw" ]] && continue
    IFS=$'\t' read -r instance health <<<"$raw"
    [[ -n "$instance" ]] && lb_health["$instance"]="${health:-UNKNOWN}"
  done

  # Split the MIG and autoscaler metadata into presentation-friendly variables.
  IFS=$'\t' read -r dr_target_size dr_stable <<<"${dr_mig_meta:-$'-\t-'}"
  IFS=$'\t' read -r autoscaler_status recommended min_replicas max_replicas <<<"${dr_autoscaler_meta:-$'-\t-\t-\t-'}"

  # ---------------------------------------------------------------------------
  # SECTION 12 - Render primary region
  #
  # Watch VM STATUS and MIG ACTION during script 03. Watch LB HEALTH during
  # script 04 when nginx is stopped but the VMs themselves remain running.
  # ---------------------------------------------------------------------------
  write_line 1 "Updated: $(date '+%Y-%m-%d %H:%M:%S %Z')   Refresh: ${INTERVAL}s   Ctrl-C to stop"
  write_line 2 "================================================================================================"
  write_line 3 "MEDICARE HA/DR LIVE DASHBOARD   Backend: ${BACKEND_SERVICE}"
  write_line 4 ""
  write_line 5 "PRIMARY - ${PRIMARY_REGION} - ${PRIMARY_MIG}"
  write_line 6 "$(format_header)"

  for ((i=0; i<PRIMARY_SLOTS; i++)); do
    write_line $((7 + i)) "$(format_instance_row "${primary_rows[$i]:-}")"
  done

  # ---------------------------------------------------------------------------
  # SECTION 13 - Render DR region
  #
  # During primary application failure, DR should remain load-balancer healthy.
  # During load generation, additional DR rows can appear as the MIG scales.
  # ---------------------------------------------------------------------------
  write_line 11 ""
  write_line 12 "DR      - ${DR_REGION} - ${DR_MIG}"
  write_line 13 "$(format_header)"

  for ((i=0; i<DR_SLOTS; i++)); do
    write_line $((14 + i)) "$(format_instance_row "${dr_rows[$i]:-}")"
  done

  # ---------------------------------------------------------------------------
  # SECTION 14 - Render DR autoscaling information and demo shortcuts
  #
  # Target size shows what the MIG is maintaining; Recommended shows what the
  # autoscaler wants. Min/Max make the configured 1-to-3 DR range visible.
  # ---------------------------------------------------------------------------
  write_line 18 ""
  write_line 19 "DR CAPACITY / AUTOSCALER"
  write_line 20 "MIG target size: ${dr_target_size:--}    Stable: ${dr_stable:--}"
  write_line 21 "Autoscaler: ${DR_AUTOSCALER}    Status: ${autoscaler_status:--}"
  write_line 22 "Recommended: ${recommended:--}    Min: ${min_replicas:--}    Max: ${max_replicas:--}"
  write_line 23 "HA: 03-delete-primary-vm.sh   DR: 04-fail-primary-region.sh   Load: 05-generate-load.sh"

  # Pause briefly, then repeat the entire collection/render cycle.
  sleep "$INTERVAL"
done
