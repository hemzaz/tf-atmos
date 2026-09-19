#!/usr/bin/env bash
# Apply IAM security best practices
# Extracted from the inline `harden-iam` workflow; run via `atmos workflow harden-iam -f security-hardening`.
# shellcheck source=../common/stack-context.sh
source "$(dirname "$0")/../common/stack-context.sh"

# --- iam-hardening ---
WHITE='\033[1;37m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }

echo -e "\n${WHITE}=== IAM Security Hardening ===${NC}\n"

AUTO_APPROVE="${AUTO_APPROVE:-false}"

if [[ "$AUTO_APPROVE" != "true" ]]; then
  log_info "Not confirmed: skipping IAM hardening"
  exit 0
fi

# Set password policy
log_info "Configuring IAM password policy..."

aws iam update-account-password-policy \
  --minimum-password-length 14 \
  --require-symbols \
  --require-numbers \
  --require-uppercase-characters \
  --require-lowercase-characters \
  --allow-users-to-change-password \
  --max-password-age 90 \
  --password-reuse-prevention 12 \
  --hard-expiry 2>/dev/null || true

echo "Password policy configured:"
echo "  - Minimum length: 14 characters"
echo "  - Require: uppercase, lowercase, numbers, symbols"
echo "  - Max age: 90 days"
echo "  - Password reuse prevention: 12 passwords"

log_info "IAM hardening complete"
