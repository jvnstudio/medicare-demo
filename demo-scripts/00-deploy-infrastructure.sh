#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# 00 - DEPLOY INFRASTRUCTURE
#
# Purpose:
#   Rebuild or update the Medicare demo environment from the Terraform stored
#   in GitHub. The script uses Google Cloud Infrastructure Manager so the
#   deployment is version-controlled, repeatable, and auditable.
#
# Flow:
#   GitHub -> Infrastructure Manager preview -> manual approval -> apply ->
#   verify deployment -> show MIGs and the global load-balancer IP.
#
# Safety:
#   Nothing is applied unless the preview succeeds and the operator explicitly
#   types DEPLOY. This script does not create or modify the IAP SSH firewall.
# =============================================================================

# -----------------------------------------------------------------------------
# SECTION 1 - Environment defaults
#
# These values point the script at the demo project, Infrastructure Manager
# deployment, Git repository, Terraform directory, and deployer service account.
# Every value can be overridden by exporting the variable before running.
# -----------------------------------------------------------------------------
PROJECT_ID="${PROJECT_ID:-medicare-demo-260907-4f00}"
REGION="${REGION:-us-east4}"
DEPLOYMENT="${DEPLOYMENT:-medicare-project}"
GIT_REPO="${GIT_REPO:-https://github.com/jvnstudio/medicare-demo.git}"
GIT_DIR="${GIT_DIR:-infra-manager/single-project}"
GIT_REF="${GIT_REF:-main}"
TF_VERSION="${TF_VERSION:-1.5.7}"
IM_SA="${IM_SA:-medicare-im-deployer@${PROJECT_ID}.iam.gserviceaccount.com}"
PREVIEW="${PREVIEW:-medicare-preview-$(date +%Y%m%d-%H%M%S)}"

# -----------------------------------------------------------------------------
# SECTION 2 - Build fully-qualified Infrastructure Manager resource names
#
# gcloud Infrastructure Manager commands use full project/location resource
# paths, so these variables keep the later commands easier to read.
# -----------------------------------------------------------------------------
DEPLOYMENT_PATH="projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT}"
PREVIEW_PATH="projects/${PROJECT_ID}/locations/${REGION}/previews/${PREVIEW}"
SA_PATH="projects/${PROJECT_ID}/serviceAccounts/${IM_SA}"

# -----------------------------------------------------------------------------
# SECTION 3 - Show the deployment target
#
# Prints the exact project, region, deployment, and Git source before anything
# is previewed or applied. This is useful during the live interview demo.
# -----------------------------------------------------------------------------
echo "Medicare GCP demo deployment"
echo "Project: ${PROJECT_ID}"
echo "Region: ${REGION}"
echo "Deployment: ${DEPLOYMENT}"
echo "Source: ${GIT_REPO} (${GIT_REF}:${GIT_DIR})"

# -----------------------------------------------------------------------------
# SECTION 4 - Select the GCP project and validate the deployer service account
#
# The first command sets the active gcloud project. The second fails early if
# the Infrastructure Manager service account is missing or inaccessible.
# -----------------------------------------------------------------------------
gcloud config set project "${PROJECT_ID}" >/dev/null

gcloud iam service-accounts describe "${IM_SA}" --project="${PROJECT_ID}" >/dev/null

# -----------------------------------------------------------------------------
# SECTION 5 - Create a Terraform preview
#
# Infrastructure Manager pulls the Terraform from GitHub and evaluates the
# proposed changes without applying the resources yet.
# -----------------------------------------------------------------------------
echo "Creating Infrastructure Manager preview..."
gcloud infra-manager previews create "${PREVIEW_PATH}" \
  --service-account="${SA_PATH}" \
  --git-source-repo="${GIT_REPO}" \
  --git-source-directory="${GIT_DIR}" \
  --git-source-ref="${GIT_REF}" \
  --input-values="project_id=${PROJECT_ID}" \
  --tf-version-constraint="=${TF_VERSION}"

# -----------------------------------------------------------------------------
# SECTION 6 - Validate the preview result
#
# The script stops here if Terraform planning fails. This prevents an apply
# from running when Infrastructure Manager reports an invalid configuration.
# -----------------------------------------------------------------------------
PREVIEW_STATE="$(gcloud infra-manager previews describe "${PREVIEW_PATH}" --format='value(state)')"
echo "Preview state: ${PREVIEW_STATE}"

if [[ "${PREVIEW_STATE}" != "SUCCEEDED" ]]; then
  echo "Preview did not succeed; no resources will be applied."
  gcloud infra-manager previews describe "${PREVIEW_PATH}" --format='yaml(state,stateDetail,errorCode,tfErrors)'
  exit 1
fi

# -----------------------------------------------------------------------------
# SECTION 7 - Manual approval gate
#
# The operator must type the exact word DEPLOY. Any other input exits cleanly
# before Infrastructure Manager applies changes to the GCP project.
# -----------------------------------------------------------------------------
read -r -p "Preview succeeded. Type DEPLOY to apply the infrastructure: " CONFIRM
if [[ "${CONFIRM}" != "DEPLOY" ]]; then
  echo "Cancelled before apply."
  exit 0
fi

# -----------------------------------------------------------------------------
# SECTION 8 - Apply the Terraform deployment
#
# Infrastructure Manager now uses the same Git commit/ref and Terraform root to
# create or update the Medicare demo resources.
# -----------------------------------------------------------------------------
echo "Applying Infrastructure Manager deployment..."
gcloud infra-manager deployments apply "${DEPLOYMENT_PATH}" \
  --service-account="${SA_PATH}" \
  --git-source-repo="${GIT_REPO}" \
  --git-source-directory="${GIT_DIR}" \
  --git-source-ref="${GIT_REF}" \
  --input-values="project_id=${PROJECT_ID}" \
  --tf-version-constraint="=${TF_VERSION}"

# -----------------------------------------------------------------------------
# SECTION 9 - Verify Infrastructure Manager reached ACTIVE
#
# ACTIVE confirms Infrastructure Manager completed the Terraform apply. If the
# state is anything else, detailed deployment errors are printed for diagnosis.
# -----------------------------------------------------------------------------
STATE="$(gcloud infra-manager deployments describe "${DEPLOYMENT_PATH}" --format='value(state)')"
echo "Deployment state: ${STATE}"

if [[ "${STATE}" != "ACTIVE" ]]; then
  gcloud infra-manager deployments describe "${DEPLOYMENT_PATH}" --format='yaml(state,stateDetail,errorCode,tfErrors)'
  exit 1
fi

# -----------------------------------------------------------------------------
# SECTION 10 - Show the resources needed for the HA/DR demonstration
#
# Lists the managed instance groups and prints the global load-balancer address
# so the operator can immediately continue with scripts 01 through 06.
# -----------------------------------------------------------------------------
echo "Managed Instance Groups:"
gcloud compute instance-groups managed list --project="${PROJECT_ID}" --format='table(name,location.basename():label=LOCATION,targetSize,status.isStable)'

echo "Global IP:"
gcloud compute addresses describe medicare-sp-global-ip --global --project="${PROJECT_ID}" --format='value(address)' || true

echo "Deployment complete."
echo "Next: cd ~/medicare-demo/demo-scripts && ./01-show-migs.sh"
