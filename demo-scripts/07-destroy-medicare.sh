#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# 07 - DESTROY MEDICARE INFRASTRUCTURE
#
# Purpose:
#   Tear down all cloud resources provisioned for the Medicare HA/DR demo.
#   Uses Google Cloud Infrastructure Manager to cleanly destroy the deployed
#   workload resources (MIGs, VMs, health checks, global load balancer, VPC)
#   and remove the deployment metadata.
#
# What this deletes:
#   - Infrastructure Manager deployment
#   - Terraform-managed infrastructure (Compute Engine VMs, MIGs, VPC, LB)
#   - Deployment metadata
#
# What this does NOT delete:
#   - The GCP project itself (leaves project, billing, IAM, and enabled APIs
#     intact so you can redeploy anytime using 00-deploy-infrastructure.sh).
# =============================================================================

# -----------------------------------------------------------------------------
# SECTION 1 - Environment defaults
# -----------------------------------------------------------------------------
PROJECT_ID="${PROJECT_ID:-medicare-demo-260907-4f00}"
REGION="${REGION:-${LOCATION:-us-east4}}"
DEPLOYMENT="${DEPLOYMENT:-medicare-project}"

# -----------------------------------------------------------------------------
# SECTION 2 - Target validation & deployment discovery
# -----------------------------------------------------------------------------
gcloud config set project "${PROJECT_ID}" >/dev/null 2>&1

DEPLOYMENT_PATH="projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT}"

# If the default deployment name doesn't exist, check for active deployments in this location
if ! gcloud infra-manager deployments describe "${DEPLOYMENT_PATH}" >/dev/null 2>&1; then
  DETECTED="$(
    gcloud infra-manager deployments list \
      --location="${REGION}" \
      --project="${PROJECT_ID}" \
      --format='value(name.basename())' 2>/dev/null \
    | head -n 1 || true
  )"
  if [[ -n "${DETECTED}" ]]; then
    DEPLOYMENT="${DETECTED}"
    DEPLOYMENT_PATH="projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT}"
  fi
fi

# -----------------------------------------------------------------------------
# SECTION 3 - Warning banner & deployment summary
# -----------------------------------------------------------------------------
echo "============================================================"
echo " WARNING: THIS WILL DESTROY MEDICARE DEMO INFRASTRUCTURE"
echo "============================================================"
echo "Project:    ${PROJECT_ID}"
echo "Region:     ${REGION}"
echo "Deployment: ${DEPLOYMENT}"
echo

echo "Current deployment status:"
if gcloud infra-manager deployments describe "${DEPLOYMENT_PATH}" >/dev/null 2>&1; then
  gcloud infra-manager deployments describe "${DEPLOYMENT_PATH}" \
    --format="table(name.basename():label=DEPLOYMENT,state:label=STATE,latestRevision.basename():label=LATEST_REVISION)"
else
  echo "No active Infrastructure Manager deployment found at:"
  echo "  ${DEPLOYMENT_PATH}"
  echo
  echo "Existing deployments in ${REGION}:"
  gcloud infra-manager deployments list \
    --location="${REGION}" \
    --project="${PROJECT_ID}" \
    --format="table(name.basename():label=NAME,state:label=STATE)" || true
  exit 0
fi

echo

# -----------------------------------------------------------------------------
# SECTION 4 - Operator confirmation gate
# -----------------------------------------------------------------------------
read -r -p "Type DELETE to destroy this deployment and all managed resources: " CONFIRM
if [[ "${CONFIRM}" != "DELETE" ]]; then
  echo "Cancelled. Nothing was deleted."
  exit 0
fi

# -----------------------------------------------------------------------------
# SECTION 5 - Pre-cleanup of standalone firewall rules
#
# If an IAP firewall rule was created manually outside Terraform, delete it
# first so it does not prevent GCP from deleting the parent VPC network.
# -----------------------------------------------------------------------------
echo
if gcloud compute firewall-rules describe "medicare-sp-allow-iap-ssh" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "Cleaning up standalone IAP firewall rule to allow clean VPC deletion..."
  gcloud compute firewall-rules delete "medicare-sp-allow-iap-ssh" --project="${PROJECT_ID}" --quiet >/dev/null 2>&1 || true
fi

# -----------------------------------------------------------------------------
# SECTION 6 - Destroy the Infrastructure Manager deployment & resources
# -----------------------------------------------------------------------------
echo "Deleting Infrastructure Manager deployment and all managed resources..."
echo "Command: gcloud infra-manager deployments delete ${DEPLOYMENT_PATH}"
echo

gcloud infra-manager deployments delete "${DEPLOYMENT_PATH}" --quiet

echo
echo "============================================================"
echo " Deployment deletion completed."
echo "============================================================"
echo

# -----------------------------------------------------------------------------
# SECTION 7 - Verify remaining deployments in region
# -----------------------------------------------------------------------------
echo "Checking for remaining Infrastructure Manager deployments..."
gcloud infra-manager deployments list \
  --location="${REGION}" \
  --project="${PROJECT_ID}" \
  --format="table(name.basename():label=DEPLOYMENT,state:label=STATE)" || true

echo
echo "Done. GCP project ${PROJECT_ID} is preserved and ready for future redeployment."
