#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-medicare-demo-260907-4f00}"
DR_REGION="${DR_REGION:-us-central1}"
DR_MIG="${DR_MIG:-medicare-sp-portal-dr}"
DR_AUTOSCALER="${DR_AUTOSCALER:-medicare-sp-dr-autoscaler}"
INTERVAL="${INTERVAL:-5}"
SLOTS="${SLOTS:-4}"
ROW_FORMAT='%-28.28s %-14.14s %-10.10s %-12.12s %-10.10s'

write_line() {
  local row="$1"
  shift
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
  IFS=$'\t' read -r instance_url status action health <<<"$raw"
  instance="${instance_url##*/}"
  zone="-"
  if [[ "$instance_url" =~ /zones/([^/]+)/instances/([^/]+)$ ]]; then
    zone="${BASH_REMATCH[1]}"
    instance="${BASH_REMATCH[2]}"
  fi

  printf "$ROW_FORMAT" \
    "${instance:--}" "${zone:--}" "${status:--}" "${action:--}" "${health:--}"
}

fetch_instances() {
  gcloud compute instance-groups managed list-instances "$DR_MIG" \
    --region="$DR_REGION" \
    --project="$PROJECT_ID" \
    --format=json 2>/dev/null \
  | jq -r '.[] | [(.instance // ""), (.instanceStatus // "-"), (.currentAction // "-"), (.healthState // "-")] | @tsv' \
  || true
}

fetch_mig_meta() {
  gcloud compute instance-groups managed describe "$DR_MIG" \
    --region="$DR_REGION" \
    --project="$PROJECT_ID" \
    --format=json 2>/dev/null \
  | jq -r '[((.targetSize // "-")|tostring), ((.status.isStable // false)|tostring)] | @tsv' \
  || true
}

fetch_autoscaler_meta() {
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
  || true
}

cleanup() {
  printf '\033[?25h\033[17;1H\n'
}
trap cleanup EXIT INT TERM

printf '\033[2J\033[H\033[?25l'

while true; do
  mapfile -t rows < <(fetch_instances)
  mig_meta="$(fetch_mig_meta)"
  autoscaler_meta="$(fetch_autoscaler_meta)"

  IFS=$'\t' read -r target_size stable <<<"${mig_meta:-$'-\t-'}"
  IFS=$'\t' read -r autoscaler_status recommended min_replicas max_replicas <<<"${autoscaler_meta:-$'-\t-\t-\t-'}"

  write_line 1 "Updated: $(date '+%Y-%m-%d %H:%M:%S %Z')   Refresh: ${INTERVAL}s   Ctrl-C to stop"
  write_line 2 "================================================================================"
  write_line 3 "DR AUTOSCALING - ${DR_REGION} - ${DR_MIG}"
  write_line 4 "$(format_header)"

  for ((i=0; i<SLOTS; i++)); do
    write_line $((5 + i)) "$(format_instance_row "${rows[$i]:-}")"
  done

  write_line 9 ""
  write_line 10 "MIG target size: ${target_size:--}    Stable: ${stable:--}"
  write_line 11 "Autoscaler: ${DR_AUTOSCALER}"
  write_line 12 "Status: ${autoscaler_status:--}    Recommended: ${recommended:--}    Min: ${min_replicas:--}    Max: ${max_replicas:--}"
  write_line 13 ""
  write_line 14 "Run 06-generate-load.sh in another terminal and watch DR capacity grow in place."

  sleep "$INTERVAL"
done
