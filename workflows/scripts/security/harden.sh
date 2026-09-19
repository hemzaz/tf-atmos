#!/usr/bin/env bash
# Apply security hardening configurations
# Extracted from the inline `harden` workflow; run via `atmos workflow harden -f security-hardening`.
# shellcheck source=../lib/stack-context.sh
source "$(dirname "$0")/../lib/stack-context.sh"

# --- enable-security-services ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_skip() { echo -e "${YELLOW}[SKIP]${NC} $*"; }

echo -e "\n${WHITE}=== Security Hardening ===${NC}\n"


AUTO_APPROVE="${AUTO_APPROVE:-false}"
DRY_RUN="${DRY_RUN:-false}"

echo "Configuration:"
echo "  Stack: ${TENANT}-${ACCOUNT}-${ENVIRONMENT}"
echo "  Region: $REGION"
echo "  Auto-Approve: $AUTO_APPROVE"
echo

if [[ "$DRY_RUN" == "true" ]]; then
  echo "[DRY RUN] Would apply security hardening"
  exit 0
fi

# =================================================================
# Enable GuardDuty
# =================================================================
log_info "Checking GuardDuty..."
GD_DETECTOR=$(aws guardduty list-detectors --region "$REGION" --query 'DetectorIds[0]' --output text 2>/dev/null || echo "")

if [[ -z "$GD_DETECTOR" ]] || [[ "$GD_DETECTOR" == "None" ]]; then
  if [[ "$AUTO_APPROVE" == "true" ]]; then
    log_info "Enabling GuardDuty..."
    DETECTOR_ID=$(aws guardduty create-detector \
      --region "$REGION" \
      --enable \
      --finding-publishing-frequency FIFTEEN_MINUTES \
      --query 'DetectorId' --output text 2>/dev/null)
    log_success "GuardDuty enabled (Detector: $DETECTOR_ID)"
  else
    log_info "GuardDuty not enabled. Confirm the workflow prompt to enable."
  fi
else
  log_skip "GuardDuty already enabled"
fi

# =================================================================
# Enable Security Hub
# =================================================================
log_info "Checking Security Hub..."
if ! aws securityhub describe-hub --region "$REGION" >/dev/null 2>&1; then
  if [[ "$AUTO_APPROVE" == "true" ]]; then
    log_info "Enabling Security Hub..."
    aws securityhub enable-security-hub \
      --region "$REGION" \
      --enable-default-standards 2>/dev/null || true
    log_success "Security Hub enabled"
  else
    log_info "Security Hub not enabled. Confirm the workflow prompt to enable."
  fi
else
  log_skip "Security Hub already enabled"
fi

# =================================================================
# Enable Default EBS Encryption
# =================================================================
log_info "Checking EBS default encryption..."
EBS_ENCRYPTION=$(aws ec2 get-ebs-encryption-by-default --region "$REGION" --query 'EbsEncryptionByDefault' --output text 2>/dev/null || echo "false")

if [[ "$EBS_ENCRYPTION" != "true" ]]; then
  if [[ "$AUTO_APPROVE" == "true" ]]; then
    log_info "Enabling default EBS encryption..."
    aws ec2 enable-ebs-encryption-by-default --region "$REGION" 2>/dev/null
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
      }' 2>/dev/null
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

VPCS=$(aws ec2 describe-vpcs --region "$REGION" --query 'Vpcs[*].VpcId' --output text 2>/dev/null | tr '\t' '\n')

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
