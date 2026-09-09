#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-medicare-demo-260907-4f00}"
PRIMARY_REGION="${PRIMARY_REGION:-us-east4}"
DR_REGION="${DR_REGION:-us-central1}"
PRIMARY_MIG="${PRIMARY_MIG:-medicare-sp-portal-primary}"
DR_MIG="${DR_MIG:-medicare-sp-portal-dr}"
DR_AUTOSCALER="${DR_AUTOSCALER:-medicare-sp-dr-autoscaler}"
BACKEND_SERVICE="${BACKEND_SERVICE:-medicare-sp-portal-backend}"
INTERVAL="${INTERVAL:-2}"

# Fixed slots keep the dashboard from shifting while VMs are deleted/recreated
# or while the DR MIG scales out.
PRIMARY_SLOTS="${PRIMARY_SLOTS:-4}"
DR_SLOTS="${DR_SLOTS:-4}"

# One format string for headers and data keeps columns aligned.
ROW_FORMAT='%-28.28s %-13.13s %-10.10s %-12.12s %-10.10s %-10.10s'

write_line() {
  local row="$1"
  shift
  printf '\033[%s;1H\033[2K%s' "$row" "$*"
}

format_header() {
  printf "$ROW_FORMAT" "INSTANCE" "ZONE" "VM STATUS" "MIG ACTION" "MIG HEALTH" "LB HEALTH"
}

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

fetch_dr_mig_meta() {
  gcloud compute instance-groups managed describe "$DR_MIG" \
    --region="$DR_REGION" \
    --project="$PROJECT_ID" \
    --format=json 2>/dev/null \
  | jq -r '[((.targetSize // "-")|tostring), ((.status.isStable // false)|tostring)] | @tsv' \
  2>/dev/null || true
}

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

cleanup() {
  printf '\033[?25h\033[25;1H\n'
}
trap cleanup EXIT INT TERM

# Clear once; all later updates rewrite fixed terminal rows in place.
printf '\033[2J\033[H\033[?25l'

declare -A lb_health

while true; do
  # Fetch all current state before touching the visible dashboard.
  mapfile -t primary_rows < <(fetch_mig_rows "$PRIMARY_MIG" "$PRIMARY_REGION")
  mapfile -t dr_rows < <(fetch_mig_rows "$DR_MIG" "$DR_REGION")
  mapfile -t current_lb_rows < <(fetch_lb_rows)
  dr_mig_meta="$(fetch_dr_mig_meta)"
  dr_autoscaler_meta="$(fetch_dr_autoscaler_meta)"

  lb_health=()
  for raw in "${current_lb_rows[@]:-}"; do
    [[ -z "$raw" ]] && continue
    IFS=$'\t' read -r instance health <<<"$raw"
    [[ -n "$instance" ]] && lb_health["$instance"]="${health:-UNKNOWN}"
  done

  IFS=$'\t' read -r dr_target_size dr_stable <<<"${dr_mig_meta:-$'-\t-'}"
  IFS=$'\t' read -r autoscaler_status recommended min_replicas max_replicas <<<"${dr_autoscaler_meta:-$'-\t-\t-\t-'}"

  write_line 1 "Updated: $(date '+%Y-%m-%d %H:%M:%S %Z')   Refresh: ${INTERVAL}s   Ctrl-C to stop"
  write_line 2 "================================================================================================"
  write_line 3 "MEDICARE HA/DR LIVE DASHBOARD   Backend: ${BACKEND_SERVICE}"
  write_line 4 ""
  write_line 5 "PRIMARY - ${PRIMARY_REGION} - ${PRIMARY_MIG}"
  write_line 6 "$(format_header)"

  for ((i=0; i<PRIMARY_SLOTS; i++)); do
    write_line $((7 + i)) "$(format_instance_row "${primary_rows[$i]:-}")"
  done

  write_line 11 ""
  write_line 12 "DR      - ${DR_REGION} - ${DR_MIG}"
  write_line 13 "$(format_header)"

  for ((i=0; i<DR_SLOTS; i++)); do
    write_line $((14 + i)) "$(format_instance_row "${dr_rows[$i]:-}")"
  done

  write_line 18 ""
  write_line 19 "DR CAPACITY / AUTOSCALER"
  write_line 20 "MIG target size: ${dr_target_size:--}    Stable: ${dr_stable:--}"
  write_line 21 "Autoscaler: ${DR_AUTOSCALER}    Status: ${autoscaler_status:--}"
  write_line 22 "Recommended: ${recommended:--}    Min: ${min_replicas:--}    Max: ${max_replicas:--}"
  write_line 23 "HA: 03-delete-primary-vm.sh   DR: 04-fail-primary-region.sh   Load: 05-generate-load.sh"

  sleep "$INTERVAL"
done
