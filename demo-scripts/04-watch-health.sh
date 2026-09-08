#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-medicare-demo-260907-4f00}"
BACKEND_SERVICE="${BACKEND_SERVICE:-medicare-sp-portal-backend}"
PRIMARY_REGION="${PRIMARY_REGION:-us-east4}"
DR_REGION="${DR_REGION:-us-central1}"
INTERVAL="${INTERVAL:-5}"
PRIMARY_SLOTS="${PRIMARY_SLOTS:-4}"
DR_SLOTS="${DR_SLOTS:-4}"

ROW_FORMAT='%-28.28s %-14.14s %-12.12s %-16.16s'

write_line() {
  local row="$1"
  shift
  printf '\033[%s;1H\033[2K%s' "$row" "$*"
}

format_header() {
  printf "$ROW_FORMAT" "INSTANCE" "ZONE" "HEALTH" "IP:PORT"
}

format_row() {
  local raw="$1"

  if [[ -z "$raw" ]]; then
    printf "$ROW_FORMAT" "-" "-" "-" "-"
    return
  fi

  local instance zone health ipport
  IFS=$'\t' read -r instance zone health ipport <<<"$raw"
  printf "$ROW_FORMAT" \
    "${instance:--}" \
    "${zone:--}" \
    "${health:--}" \
    "${ipport:--}"
}

fetch_health_rows() {
  gcloud compute backend-services get-health "$BACKEND_SERVICE" \
    --global \
    --project="$PROJECT_ID" \
    --format=json 2>/dev/null \
  | jq -r '
      .[]?
      | .status.healthStatus[]?
      | [
          ((.instance // "") | split("/")[-1]),
          ((.instance // "") | capture("/zones/(?<z>[^/]+)/instances/").z // "-"),
          (.healthState // "UNKNOWN"),
          (((.ipAddress // "-")|tostring) + ":" + ((.port // "-")|tostring))
        ]
      | @tsv
    ' 2>/dev/null || true
}

cleanup() {
  printf '\033[?25h\033[20;1H\n'
}
trap cleanup EXIT INT TERM

# Clear once. All dashboard rows are rewritten in place after this.
printf '\033[2J\033[H\033[?25l'

while true; do
  mapfile -t all_rows < <(fetch_health_rows)

  primary_rows=()
  dr_rows=()

  for raw in "${all_rows[@]:-}"; do
    [[ -z "$raw" ]] && continue
    zone="$(awk -F'\t' '{print $2}' <<<"$raw")"

    if [[ "$zone" == "$PRIMARY_REGION"-* ]]; then
      primary_rows+=("$raw")
    elif [[ "$zone" == "$DR_REGION"-* ]]; then
      dr_rows+=("$raw")
    fi
  done

  write_line 1 "Updated: $(date '+%Y-%m-%d %H:%M:%S %Z')   Refresh: ${INTERVAL}s   Ctrl-C to stop"
  write_line 2 "================================================================================"
  write_line 3 "GLOBAL BACKEND HEALTH - ${BACKEND_SERVICE}"
  write_line 4 ""
  write_line 5 "PRIMARY BACKEND - ${PRIMARY_REGION}"
  write_line 6 "$(format_header)"

  for ((i=0; i<PRIMARY_SLOTS; i++)); do
    write_line $((7 + i)) "$(format_row "${primary_rows[$i]:-}")"
  done

  write_line 11 ""
  write_line 12 "DR BACKEND      - ${DR_REGION}"
  write_line 13 "$(format_header)"

  for ((i=0; i<DR_SLOTS; i++)); do
    write_line $((14 + i)) "$(format_row "${dr_rows[$i]:-}")"
  done

  write_line 18 ""
  write_line 19 "Fail the primary application in another terminal; watch HEALTH change in place."

  sleep "$INTERVAL"
done
