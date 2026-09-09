#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-medicare-demo-260907-4f00}"
REGION="${REGION:-us-east4}"
DEPLOYMENT="${DEPLOYMENT:-medicare-project}"
GIT_REPO="${GIT_REPO:-https://github.com/jvnstudio/medicare-demo.git}"
GIT_DIR="${GIT_DIR:-infra-manager/single-project}"
GIT_REF="${GIT_REF:-main}"
TF_VERSION="${TF_VERSION:-1.5.7}"
IM_SA="${IM_SA:-medicare-im-deployer@${PROJECT_ID}.iam.gserviceaccount.com}"
PREVIEW="${PREVIEW:-medicare-preview-$(date +%Y%m%d-%H%M%S)}"

DEPLOYMENT_PATH="projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT}"
PREVIEW_PATH="projects/${PROJECT_ID}/locations/${REGION}/previews/${PREVIEW}"
SA_PATH="projects/${PROJECT_ID}/serviceAccounts/${IM_SA}"

echo "Medicare GCP demo deployment"
echo "Project: ${PROJECT_ID}"
echo "Region: ${REGION}"
echo "Deployment: ${DEPLOYMENT}"
echo "Source: ${GIT_REPO} (${GIT_REF}:${GIT_DIR})"

gcloud config set project "${PROJECT_ID}" >/dev/null

gcloud iam service-accounts describe "${IM_SA}" --project="${PROJECT_ID}" >/dev/null

echo "Creating Infrastructure Manager preview..."
gcloud infra-manager previews create "${PREVIEW_PATH}" \
  --service-account="${SA_PATH}" \
  --git-source-repo="${GIT_REPO}" \
  --git-source-directory="${GIT_DIR}" \
  --git-source-ref="${GIT_REF}" \
  --input-values="project_id=${PROJECT_ID}" \
  --tf-version-constraint="=${TF_VERSION}"

PREVIEW_STATE="$(gcloud infra-manager previews describe "${PREVIEW_PATH}" --format='value(state)')"
echo "Preview state: ${PREVIEW_STATE}"

if [[ "${PREVIEW_STATE}" != "SUCCEEDED" ]]; then
  echo "Preview did not succeed; no resources will be applied."
  gcloud infra-manager previews describe "${PREVIEW_PATH}" --format='yaml(state,stateDetail,errorCode,tfErrors)'
  exit 1
fi

read -r -p "Preview succeeded. Type DEPLOY to apply the infrastructure: " CONFIRM
if [[ "${CONFIRM}" != "DEPLOY" ]]; then
  echo "Cancelled before apply."
  exit 0
fi

echo "Applying Infrastructure Manager deployment..."
gcloud infra-manager deployments apply "${DEPLOYMENT_PATH}" \
  --service-account="${SA_PATH}" \
  --git-source-repo="${GIT_REPO}" \
  --git-source-directory="${GIT_DIR}" \
  --git-source-ref="${GIT_REF}" \
  --input-values="project_id=${PROJECT_ID}" \
  --tf-version-constraint="=${TF_VERSION}"

STATE="$(gcloud infra-manager deployments describe "${DEPLOYMENT_PATH}" --format='value(state)')"
echo "Deployment state: ${STATE}"

if [[ "${STATE}" != "ACTIVE" ]]; then
  gcloud infra-manager deployments describe "${DEPLOYMENT_PATH}" --format='yaml(state,stateDetail,errorCode,tfErrors)'
  exit 1
fi

echo "Managed Instance Groups:"
gcloud compute instance-groups managed list --project="${PROJECT_ID}" --format='table(name,location.basename():label=LOCATION,targetSize,status.isStable)'

echo "Global IP:"
gcloud compute addresses describe medicare-sp-global-ip --global --project="${PROJECT_ID}" --format='value(address)' || true

echo "Deployment complete."
echo "Next: cd ~/medicare-demo/demo-scripts && ./01-show-migs.sh"
