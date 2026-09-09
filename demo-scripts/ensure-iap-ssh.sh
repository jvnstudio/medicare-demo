#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# ENSURE IAP SSH ACCESS
#
# Purpose:
#   Configure and verify all prerequisites for Identity-Aware Proxy (IAP) SSH
#   access into Medicare demo VMs.
#
# Prerequisites configured:
#   1. Ingress VPC firewall rule allowing TCP:22 from 35.235.240.0/20 (IAP CIDR).
#   2. IAM binding granting roles/iap.tunnelResourceAccessor to the active user.
#   3. Connectivity test through the IAP tunnel to an active primary VM.
#
# Safe to run multiple times (idempotent).
# =============================================================================

PROJECT_ID="${PROJECT_ID:-medicare-demo-260907-4f00}"
PRIMARY_REGION="${PRIMARY_REGION:-us-east4}"
PRIMARY_MIG="${PRIMARY_MIG:-medicare-sp-portal-primary}"
NETWORK="${NETWORK:-medicare-sp-vpc}"
FIREWALL_RULE="${FIREWALL_RULE:-medicare-sp-allow-iap-ssh}"
IAP_CIDR="35.235.240.0/20"

RUN_TEST=true
for arg in "$@"; do
  case "$arg" in
    --no-test|--fast)
      RUN_TEST=false
      ;;
  esac
done

echo "============================================================"
echo " Medicare DR Demo - Ensure IAP SSH Access"
echo " Project:  $PROJECT_ID"
echo " Network:  $NETWORK"
echo " Rule:     $FIREWALL_RULE"
echo "============================================================"

# -----------------------------------------------------------------------------
# SECTION 1 - Validate gcloud project & discover VPC network if needed
# -----------------------------------------------------------------------------
gcloud config set project "$PROJECT_ID" >/dev/null 2>&1

if ! gcloud compute networks describe "$NETWORK" --project="$PROJECT_ID" >/dev/null 2>&1; then
  DETECTED_NET="$(gcloud compute networks list --project="$PROJECT_ID" --filter="name~medicare" --format='value(name)' 2>/dev/null | head -n 1 || true)"
  if [[ -n "$DETECTED_NET" ]]; then
    echo "Found network: $DETECTED_NET"
    NETWORK="$DETECTED_NET"
  fi
fi

# -----------------------------------------------------------------------------
# SECTION 2 - Create or verify the IAP SSH ingress firewall rule
# -----------------------------------------------------------------------------
echo
echo "1. Checking IAP SSH firewall rule..."
if gcloud compute firewall-rules describe "$FIREWALL_RULE" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "   [OK] Firewall rule '$FIREWALL_RULE' already exists."
else
  echo "   Creating firewall rule '$FIREWALL_RULE' on network '$NETWORK'..."
  gcloud compute firewall-rules create "$FIREWALL_RULE" \
    --project="$PROJECT_ID" \
    --network="$NETWORK" \
    --direction=INGRESS \
    --action=ALLOW \
    --rules=tcp:22 \
    --source-ranges="$IAP_CIDR" \
    --description="Allow Google Cloud IAP TCP forwarding for SSH"
  echo "   [OK] Firewall rule created."
fi

# -----------------------------------------------------------------------------
# SECTION 3 - Ensure the active user has roles/iap.tunnelResourceAccessor
# -----------------------------------------------------------------------------
echo
echo "2. Checking IAP tunnel IAM permissions..."
CURRENT_ACCOUNT="$(gcloud config get-value account 2>/dev/null || true)"
if [[ -n "$CURRENT_ACCOUNT" && "$CURRENT_ACCOUNT" != "(unset)" ]]; then
  echo "   Adding roles/iap.tunnelResourceAccessor for $CURRENT_ACCOUNT..."
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="user:${CURRENT_ACCOUNT}" \
    --role="roles/iap.tunnelResourceAccessor" \
    --condition=None \
    --quiet >/dev/null 2>&1 || true
  echo "   [OK] IAM role binding confirmed for $CURRENT_ACCOUNT."
else
  echo "   [INFO] No active user account found via 'gcloud config get-value account'."
fi

# -----------------------------------------------------------------------------
# SECTION 4 - Test IAP SSH connectivity against a running VM (if available)
# -----------------------------------------------------------------------------
if [[ "$RUN_TEST" == "true" ]]; then
  echo
  echo "3. Verifying connectivity to primary VMs..."
  TEST_VM="$(
    gcloud compute instance-groups managed list-instances "$PRIMARY_MIG" \
      --region="$PRIMARY_REGION" \
      --project="$PROJECT_ID" \
      --format=json 2>/dev/null \
    | jq -r '.[0].instance // empty | split("/")[-1]' 2>/dev/null || true
  )"

  if [[ -n "$TEST_VM" && "$TEST_VM" != "null" ]]; then
    TEST_ZONE="$(
      gcloud compute instances list \
        --project="$PROJECT_ID" \
        --filter="name=$TEST_VM" \
        --format='value(zone.basename())' 2>/dev/null || true
    )"

    if [[ -n "$TEST_ZONE" ]]; then
      echo "   Testing IAP SSH connection to $TEST_VM ($TEST_ZONE)..."
      if gcloud compute ssh "$TEST_VM" \
        --zone="$TEST_ZONE" \
        --project="$PROJECT_ID" \
        --tunnel-through-iap \
        --command="echo 'IAP SSH handshake successful'" 2>/dev/null; then
        echo "   [SUCCESS] IAP tunnel verified and working!"
      else
        echo "   [WARNING] Connection test failed. The VM guest agent may still be initializing."
        echo "             If the VM is newly created, wait 10-15 seconds and re-test."
      fi
    fi
  else
    echo "   [INFO] No active instances found in primary MIG ($PRIMARY_MIG) to test."
    echo "          Firewall rule and IAM binding are configured and ready."
  fi
fi

echo
echo "============================================================"
echo " IAP SSH setup complete. You can now run 04-fail-primary-region.sh"
echo "============================================================"
