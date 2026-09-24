#!/usr/bin/env bash
# Apply security hardening configurations
# Extracted from the inline `harden` workflow; run via `atmos workflow harden -f security-hardening`.
#
# HARDEN_PHASE picks what runs:
#   plan  - plan every owned component and print the plans, change nothing
#           (the workflow runs this BEFORE its confirm prompt)
#   apply - apply exactly the planfiles the plan phase saved (after confirm)
#   all   - (default, standalone use) plan and print, then apply when
#           AUTO_APPROVE=true
set -euo pipefail

# shellcheck source=../common/stack-context.sh
source "$(dirname "$0")/../common/stack-context.sh"

# --- enable-security-services ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_skip() { echo -e "${YELLOW}[SKIP]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

echo -e "\n${WHITE}=== Security Hardening ===${NC}\n"


AUTO_APPROVE="${AUTO_APPROVE:-false}"
DRY_RUN="${DRY_RUN:-false}"
HARDEN_PHASE="${HARDEN_PHASE:-all}"
case "$HARDEN_PHASE" in
  plan | apply | all) ;;
  *)
    echo "HARDEN_PHASE must be plan, apply or all (got: ${HARDEN_PHASE})" >&2
    exit 1
    ;;
esac

# Owned by these components, deployed in every stack. Creating the services
# with the aws CLI instead would leave Terraform failing with "already exists"
# on its next apply, so hardening deploys the components and never touches the
# services directly.
COMPONENTS=(guardduty/main securityhub/main)

echo "Configuration:"
echo "  Stack: ${TENANT}-${ACCOUNT}-${ENVIRONMENT}"
echo "  Region: $REGION"
echo "  Auto-Approve: $AUTO_APPROVE"
echo "  Phase: $HARDEN_PHASE"
echo

if [[ "$DRY_RUN" == "true" ]]; then
  echo "[DRY RUN] Would apply security hardening"
  exit 0
fi

# =================================================================
# GuardDuty and Security Hub
# =================================================================
# Plan first and print the plan (atmos saves the planfile), so what is
# confirmed is what is applied: the apply step uses --from-plan, and Terraform
# rejects a planfile that went stale in between.
if [[ "$HARDEN_PHASE" != "apply" ]]; then
  for component in "${COMPONENTS[@]}"; do
    log_info "Planning ${component} in ${STACK}..."
    atmos terraform plan "$component" -s "$STACK"
  done
fi

if [[ "$HARDEN_PHASE" == "plan" ]]; then
  log_info "Plans above are saved. Confirm the workflow prompt to apply them."
  exit 0
fi

for component in "${COMPONENTS[@]}"; do
  if [[ "$AUTO_APPROVE" == "true" ]]; then
    log_info "Applying the saved ${component} plan to ${STACK}..."
    atmos terraform deploy "$component" -s "$STACK" --from-plan
    log_success "${component} deployed"
  else
    log_info "${component} not deployed. Confirm the workflow prompt, or run: atmos terraform deploy ${component} -s ${STACK}"
  fi
done

# Report (read-only): what is actually enabled in the account/region now.
log_info "GuardDuty / Security Hub status in ${REGION}:"
GD_DETECTOR=$(aws guardduty list-detectors --region "$REGION" --query 'DetectorIds[0]' --output text 2>/dev/null || echo "None")
if [[ -n "$GD_DETECTOR" ]] && [[ "$GD_DETECTOR" != "None" ]]; then
  GD_STATUS=$(aws guardduty get-detector --region "$REGION" --detector-id "$GD_DETECTOR" --query 'Status' --output text 2>/dev/null || echo "unknown")
  echo "  GuardDuty:    detector ${GD_DETECTOR} (${GD_STATUS})"
else
  echo "  GuardDuty:    no detector"
fi
SH_HUB=$(aws securityhub describe-hub --region "$REGION" --query 'HubArn' --output text 2>/dev/null || echo "")
if [[ -n "$SH_HUB" ]] && [[ "$SH_HUB" != "None" ]]; then
  SH_STANDARDS_RAW=$(aws securityhub get-enabled-standards --region "$REGION" \
    --query 'StandardsSubscriptions[].StandardsArn' --output text 2>/dev/null || echo "unknown")
  SH_STANDARDS=$(tr '\t' '\n' <<<"$SH_STANDARDS_RAW" | sed 's|.*:standards/||; s|.*:ruleset/||' | paste -sd, -)
  echo "  Security Hub: ${SH_HUB} (standards: ${SH_STANDARDS:-none})"
else
  echo "  Security Hub: not enabled"
fi

# =================================================================
# Enable Default EBS Encryption
# =================================================================
log_info "Checking EBS default encryption..."
EBS_ENCRYPTION=$(aws ec2 get-ebs-encryption-by-default --region "$REGION" --query 'EbsEncryptionByDefault' --output text 2>/dev/null || echo "false")

if [[ "$EBS_ENCRYPTION" != "true" ]]; then
  if [[ "$AUTO_APPROVE" == "true" ]]; then
    log_info "Enabling default EBS encryption..."
    aws ec2 enable-ebs-encryption-by-default --region "$REGION" ||
      { log_error "Enabling default EBS encryption in ${REGION} failed (see the aws error above)"; exit 1; }
    log_success "Default EBS encryption enabled"
  else
    log_info "EBS encryption not enabled. Confirm the workflow prompt to enable."
  fi
else
  log_skip "EBS default encryption already enabled"
fi

# =================================================================
# Enable S3 Block Public Access (Account Level)
# =================================================================
log_info "Checking S3 account-level public access block..."
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)

S3_BLOCK=$(aws s3control get-public-access-block --account-id "$ACCOUNT_ID" 2>/dev/null || echo "none")

if [[ "$S3_BLOCK" == "none" ]]; then
  if [[ "$AUTO_APPROVE" == "true" ]]; then
    log_info "Enabling S3 account-level public access block..."
    aws s3control put-public-access-block \
      --account-id "$ACCOUNT_ID" \
      --public-access-block-configuration '{
        "BlockPublicAcls": true,
        "IgnorePublicAcls": true,
        "BlockPublicPolicy": true,
        "RestrictPublicBuckets": true
      }' ||
      { log_error "Setting the S3 account public access block on ${ACCOUNT_ID} failed (see the aws error above)"; exit 1; }
    log_success "S3 public access block enabled"
  else
    log_info "S3 public access block not configured. Confirm the workflow prompt to enable."
  fi
else
  log_skip "S3 public access block already configured"
fi

log_success "Security hardening complete"

# --- harden-network ---
echo -e "\n${WHITE}=== Network Security Hardening ===${NC}\n"

AUTO_APPROVE="${AUTO_APPROVE:-false}"

if [[ "$AUTO_APPROVE" != "true" ]]; then
  log_info "Network hardening skipped. Confirm the workflow prompt to apply."
  exit 0
fi

# Find security groups with wide-open rules
log_info "Scanning for overly permissive security groups..."

OPEN_SGS=$(aws ec2 describe-security-groups --region "$REGION" \
  --query "SecurityGroups[?IpPermissions[?IpRanges[?CidrIp=='0.0.0.0/0'] && (FromPort==22 || FromPort==3389)]].GroupId" \
  --output text 2>/dev/null || echo "")

if [[ -n "$OPEN_SGS" ]]; then
  echo "Found security groups with wide-open SSH/RDP:"
  echo "$OPEN_SGS"
  echo
  echo "WARNING: These should be reviewed and restricted manually."
  echo "Automated remediation of security groups is not safe without review."
else
  log_success "No overly permissive security groups found"
fi

# Check for VPCs without flow logs
log_info "Checking VPC flow logs..."

VPCS=$(aws ec2 describe-vpcs --region "$REGION" --query 'Vpcs[*].VpcId' --output text 2>/dev/null | tr '\t' '\n' || echo "")

for vpc in $VPCS; do
  HAS_FLOW_LOG=$(aws ec2 describe-flow-logs --region "$REGION" \
    --filter "Name=resource-id,Values=$vpc" \
    --query 'FlowLogs[0].FlowLogId' --output text 2>/dev/null || echo "")

  if [[ -z "$HAS_FLOW_LOG" ]] || [[ "$HAS_FLOW_LOG" == "None" ]]; then
    log_info "VPC $vpc missing flow logs"
    echo "  Consider enabling via Terraform/Atmos VPC component"
  fi
done

log_success "Network security review complete"
