#!/usr/bin/env bash
set -euo pipefail

: "${PROJECT_ID:?Set PROJECT_ID to the existing GCP project}"

IM_SA_NAME="${IM_SA_NAME:-medicare-im-deployer}"
IM_SA_EMAIL="${IM_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
ACTIVE_ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' | head -n1)"

if [[ -z "${ACTIVE_ACCOUNT}" ]]; then
  echo "ERROR: No active gcloud account." >&2
  exit 1
fi

gcloud config set project "${PROJECT_ID}"

gcloud services enable \
  config.googleapis.com \
  serviceusage.googleapis.com \
  compute.googleapis.com \
  storage.googleapis.com

if ! gcloud iam service-accounts describe "${IM_SA_EMAIL}" >/dev/null 2>&1; then
  gcloud iam service-accounts create "${IM_SA_NAME}" \
    --display-name="Medicare Infrastructure Manager Deployer"
fi

# Caller can run Infrastructure Manager with the execution service account.
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="user:${ACTIVE_ACCOUNT}" \
  --role="roles/config.admin" \
  --condition=None --quiet

gcloud iam service-accounts add-iam-policy-binding "${IM_SA_EMAIL}" \
  --member="user:${ACTIVE_ACCOUNT}" \
  --role="roles/iam.serviceAccountUser" \
  --condition=None --quiet

# Infrastructure Manager runtime and resource-management permissions.
for role in \
  roles/config.agent \
  roles/serviceusage.serviceUsageAdmin \
  roles/compute.admin \
  roles/storage.admin \
  roles/container.admin \
  roles/file.editor \
  roles/iam.serviceAccountUser; do
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${IM_SA_EMAIL}" \
    --role="${role}" \
    --condition=None --quiet
done

cat <<EOF

Single-project Infrastructure Manager bootstrap complete.
Project:      ${PROJECT_ID}
Execution SA: ${IM_SA_EMAIL}

Use this Git directory in Infrastructure Manager:
  infra-manager/single-project

Required deployment input:
  project_id=${PROJECT_ID}

HA/DR defaults:
  primary_region=us-east4
  dr_region=us-central1
  vm_target_size=2
  enable_dr=true
  dr_max_replicas=3
  lb_max_rate_per_instance=5
  dr_lb_target_utilization=0.6

Optional services remain disabled by default:
  enable_gke=false
  enable_filestore=false
EOF
