#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
PRIMARY_REGION="${PRIMARY_REGION:-us-east4}"
DR_REGION="${DR_REGION:-us-central1}"
PRIMARY_MIG="${PRIMARY_MIG:-medicare-sp-portal-primary}"
DR_MIG="${DR_MIG:-medicare-sp-portal-dr}"
LB_ADDRESS_NAME="${LB_ADDRESS_NAME:-medicare-sp-global-ip}"

if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "(unset)" ]]; then
  echo "ERROR: Set PROJECT_ID or configure a gcloud project." >&2
  exit 1
fi

LB_IP="$(gcloud compute addresses describe "${LB_ADDRESS_NAME}" \
  --global \
  --project="${PROJECT_ID}" \
  --format='value(address)')"

printf '\nMedicare HA/DR demo\n'
printf 'Project:        %s\n' "${PROJECT_ID}"
printf 'Primary MIG:    %s (%s)\n' "${PRIMARY_MIG}" "${PRIMARY_REGION}"
printf 'DR MIG:         %s (%s)\n' "${DR_MIG}" "${DR_REGION}"
printf 'Global LB IP:   %s\n\n' "${LB_IP}"

printf '==> Primary instances\n'
gcloud compute instance-groups managed list-instances "${PRIMARY_MIG}" \
  --region="${PRIMARY_REGION}" \
  --project="${PROJECT_ID}"

printf '\n==> DR instances\n'
gcloud compute instance-groups managed list-instances "${DR_MIG}" \
  --region="${DR_REGION}" \
  --project="${PROJECT_ID}"

printf '\n==> Current load-balanced response\n'
curl -sS --max-time 10 "http://${LB_IP}/" | grep -E '<p>(Instance|Zone|Region|HA/DR):' || true

printf '\nThis test stops nginx on every PRIMARY managed VM.\n'
printf 'The VMs stay managed by the MIG; application health checks should trigger\n'
printf 'both load-balancer failover to DR and primary MIG autohealing.\n\n'
read -r -p 'Type FAILOVER to continue: ' CONFIRM

if [[ "${CONFIRM}" != "FAILOVER" ]]; then
  echo "Cancelled."
  exit 0
fi

mapfile -t PRIMARY_INSTANCE_URLS < <(
  gcloud compute instance-groups managed list-instances "${PRIMARY_MIG}" \
    --region="${PRIMARY_REGION}" \
    --project="${PROJECT_ID}" \
    --format='value(instance)'
)

if [[ "${#PRIMARY_INSTANCE_URLS[@]}" -eq 0 ]]; then
  echo "ERROR: No primary instances found." >&2
  exit 1
fi

printf '\n==> Stopping nginx on primary VMs\n'
for INSTANCE_URL in "${PRIMARY_INSTANCE_URLS[@]}"; do
  INSTANCE_NAME="${INSTANCE_URL##*/}"
  INSTANCE_ZONE="$(awk -F/ '{for (i=1; i<=NF; i++) if ($i == "zones") {print $(i+1); exit}}' <<<"${INSTANCE_URL}")"

  printf 'Stopping nginx on %s (%s)\n' "${INSTANCE_NAME}" "${INSTANCE_ZONE}"
  gcloud compute ssh "${INSTANCE_NAME}" \
    --zone="${INSTANCE_ZONE}" \
    --project="${PROJECT_ID}" \
    --command='sudo systemctl stop nginx' \
    --quiet || echo "WARNING: SSH command failed for ${INSTANCE_NAME}; continue watching health."
done

printf '\n==> Watching the global endpoint for DR service\n'
printf 'Health detection and DNS-free global load-balancer failover can take a short period.\n\n'

FAILED_OVER=0
for ATTEMPT in $(seq 1 36); do
  BODY="$(curl -s --max-time 5 "http://${LB_IP}/" || true)"
  REGION="$(sed -n 's/.*<p>Region: \([^<]*\)<\/p>.*/\1/p' <<<"${BODY}" | head -n1)"
  INSTANCE="$(sed -n 's/.*<p>Instance: \([^<]*\)<\/p>.*/\1/p' <<<"${BODY}" | head -n1)"

  printf '%s  attempt=%02d  region=%-12s instance=%s\n' \
    "$(date '+%H:%M:%S')" "${ATTEMPT}" "${REGION:-unavailable}" "${INSTANCE:-unavailable}"

  if [[ "${REGION}" == "${DR_REGION}" ]]; then
    FAILED_OVER=1
    break
  fi
  sleep 5
done

if [[ "${FAILED_OVER}" -eq 1 ]]; then
  printf '\nSUCCESS: traffic is being served from DR region %s.\n' "${DR_REGION}"
else
  printf '\nDR was not observed within the watch window. Check backend health and MIG actions.\n'
fi

cat <<EOF

Useful follow-up commands:

Watch primary autohealing:
  watch -n 5 'gcloud compute instance-groups managed list-instances ${PRIMARY_MIG} --region=${PRIMARY_REGION} --project=${PROJECT_ID}'

Watch DR capacity:
  watch -n 5 'gcloud compute instance-groups managed list-instances ${DR_MIG} --region=${DR_REGION} --project=${PROJECT_ID}'

Generate sustained requests after failover to demonstrate DR scale-out:
  seq 1 3000 | xargs -P 40 -I{} curl -s --max-time 5 http://${LB_IP}/ >/dev/null

Inspect the DR autoscaler:
  gcloud compute instance-groups managed describe ${DR_MIG} --region=${DR_REGION} --project=${PROJECT_ID}

The primary MIG should repair/recreate unhealthy VMs automatically. Once primary
health returns, the global load balancer should again prefer the nearer healthy
primary backend for East Coast requests.
EOF
