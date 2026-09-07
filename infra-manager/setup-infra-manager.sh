#!/usr/bin/env bash
set -euo pipefail

: "${PROJECT_ID:?Set PROJECT_ID to the project that will host Infrastructure Manager deployments}"
: "${FAST_ORG_ID:?Set FAST_ORG_ID to the Google Cloud organization numeric ID}"
: "${FAST_BILLING_ACCOUNT:?Set FAST_BILLING_ACCOUNT to the billing account ID}"

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
  cloudbuild.googleapis.com \
  cloudbilling.googleapis.com \
  cloudresourcemanager.googleapis.com \
  iam.googleapis.com \
  serviceusage.googleapis.com

if ! gcloud iam service-accounts describe "${IM_SA_EMAIL}" >/dev/null 2>&1; then
  gcloud iam service-accounts create "${IM_SA_NAME}" \
    --display-name="Medicare Infrastructure Manager Deployer"
fi

# Caller permissions to operate Infrastructure Manager and act as its execution SA.
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="user:${ACTIVE_ACCOUNT}" \
  --role="roles/config.admin" \
  --condition=None --quiet

gcloud iam service-accounts add-iam-policy-binding "${IM_SA_EMAIL}" \
  --member="user:${ACTIVE_ACCOUNT}" \
  --role="roles/iam.serviceAccountUser" \
  --condition=None --quiet

# Infrastructure Manager runtime permission on its host project.
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${IM_SA_EMAIL}" \
  --role="roles/config.agent" \
  --condition=None --quiet

# Landing-zone permissions. These are powerful organization bootstrap grants.
for role in \
  roles/resourcemanager.folderAdmin \
  roles/resourcemanager.projectCreator \
  roles/compute.xpnAdmin \
  roles/serviceusage.serviceUsageAdmin; do
  gcloud organizations add-iam-policy-binding "${FAST_ORG_ID}" \
    --member="serviceAccount:${IM_SA_EMAIL}" \
    --role="${role}" \
    --condition=None --quiet
done

gcloud billing accounts add-iam-policy-binding "${FAST_BILLING_ACCOUNT}" \
  --member="serviceAccount:${IM_SA_EMAIL}" \
  --role="roles/billing.user" \
  --condition=None --quiet

cat <<EOF

Infrastructure Manager bootstrap complete.
Host project:       ${PROJECT_ID}
Organization:       ${FAST_ORG_ID}
Billing account:    ${FAST_BILLING_ACCOUNT}
Execution SA:       ${IM_SA_EMAIL}

Export for later commands:
  export IM_SA_EMAIL='${IM_SA_EMAIL}'
EOF
