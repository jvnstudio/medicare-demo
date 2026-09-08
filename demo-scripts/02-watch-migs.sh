#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-medicare-demo-260907-4f00}"
PRIMARY_REGION="${PRIMARY_REGION:-us-east4}"
DR_REGION="${DR_REGION:-us-central1}"
PRIMARY_MIG="${PRIMARY_MIG:-medicare-sp-portal-primary}"
DR_MIG="${DR_MIG:-medicare-sp-portal-dr}"
INTERVAL="${INTERVAL:-2}"

# Fixed number of screen rows so the dashboard never shifts vertically.
PRIMARY_SLOTS="${PRIMARY_SLOTS:-4}"
DR_SLOTS="${DR_SLOTS:-4}"

# One format string for BOTH headers and data keeps every column aligned.
ROW_FORMAT='%-28.28s %-13.13s %-10.10s %-13.13s %-10.10s'

fetch_mig() {
  local mig="$1"
  local region="$2"

  # Return the full instance URL and parse the zone ourselves. This avoids
  # gcloud scope() formatting differences between table and CSV output.
  gcloud compute instance-groups managed list-instances "$mig" \
    --region="$region" \
    --project="$PROJECT_ID" \
    --format="csv[no-heading](instance,instanceStatus,currentAction,healthState)" \
    2>/dev/null || true
}

write_line() {
  local row="$1"
  shift
  # Move to a fixed terminal row, erase that row only, then write its new value.
  printf '\033[%s;1H\033[2K%s' "$row" "$*"
}

format_header() {
  printf "$ROW_FORMAT" "INSTANCE" "ZONE" "STATUS" "ACTION" "HEALTH"
}

format_instance_row() {
  local raw="$1"

  if [[ -z "$raw" ]]; then
    printf "$ROW_FORMAT" "-" "-" "-" "-" "-"
    return
  fi

  local instance_url status action health instance zone
  IFS=',' read -r instance_url status action health <<<"$raw"

  instance="${instance_url##*/}"
  zone="-"

  # Example URL:
  # https://www.googleapis.com/compute/v1/projects/.../zones/us-east4-a/instances/medicare-sp-portal-xxxx
  if [[ "$instance_url" =~ /zones/([^/]+)/instances/([^/]+)$ ]]; then
    zone="${BASH_REMATCH[1]}"
    instance="${BASH_REMATCH[2]}"
  fi

  printf "$ROW_FORMAT" \
    "${instance:--}" \
    "${zone:--}" \
    "${status:--}" \
    "${action:--}" \
    "${health:--}"
}

cleanup() {
  # Restore the cursor and leave the prompt below the dashboard.
  printf '\033[?25h\033[18;1H\n'
}
trap cleanup EXIT INT TERM

# Clear the terminal ONCE. After this, every value is rewritten at a fixed row.
printf '\033[2J\033[H\033[?25l'

while true; do
  # Fetch first. The existing dashboard remains untouched while gcloud runs.
  mapfile -t primary_rows < <(fetch_mig "$PRIMARY_MIG" "$PRIMARY_REGION")
  mapfile -t dr_rows < <(fetch_mig "$DR_MIG" "$DR_REGION")

  # Only values on these fixed rows are overwritten; nothing scrolls.
  write_line 1 "Updated: $(date '+%Y-%m-%d %H:%M:%S %Z')   Refresh: ${INTERVAL}s   Ctrl-C to stop"
  write_line 2 "================================================================================"
  write_line 3 "PRIMARY MIG - ${PRIMARY_REGION} - ${PRIMARY_MIG}"
  write_line 4 "$(format_header)"

  for ((i=0; i<PRIMARY_SLOTS; i++)); do
    write_line $((5 + i)) "$(format_instance_row "${primary_rows[$i]:-}")"
  done

  write_line 9 ""
  write_line 10 "DR MIG      - ${DR_REGION} - ${DR_MIG}"
  write_line 11 "$(format_header)"

  for ((i=0; i<DR_SLOTS; i++)); do
    write_line $((12 + i)) "$(format_instance_row "${dr_rows[$i]:-}")"
  done

  write_line 16 ""
  write_line 17 "Delete a primary VM in another terminal; watch STATUS / ACTION / HEALTH change in place."

  sleep "$INTERVAL"
done
