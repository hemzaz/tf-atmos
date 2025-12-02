#!/usr/bin/env bash
# =============================================================================
# Atmos Infrastructure Quickstart Script
# =============================================================================
# One-command deployment for complete infrastructure environment
#
# Usage:
#   ./scripts/quickstart.sh --tenant fnx --account dev --environment testenv-01
#   ./scripts/quickstart.sh --tenant fnx --account prod --environment production --region eu-west-2
#   ./scripts/quickstart.sh --help
#
# This script will:
#   1. Check all prerequisites (AWS CLI, Terraform, Atmos)
#   2. Validate AWS credentials and permissions
#   3. Create backend infrastructure (S3 bucket, DynamoDB table)
#   4. Deploy complete infrastructure stack
#   5. Run health checks and output endpoints
# =============================================================================

set -euo pipefail

# Script metadata
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
DEFAULT_REGION="eu-west-2"
DEFAULT_TERRAFORM_VERSION="1.11.0"
DEFAULT_ATMOS_VERSION="1.163.0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_step() {
    echo -e "\n${CYAN}${BOLD}=== $* ===${NC}\n"
}

# Print banner
print_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
    _   _                        ___        _      _        _             _
   / \ | |_ _ __ ___   ___  ___ / _ \ _   _(_) ___| | _____| |_ __ _ _ __| |_
  / _ \| __| '_ ` _ \ / _ \/ __| | | | | | | |/ __| |/ / __| __/ _` | '__| __|
 / ___ \ |_| | | | | | (_) \__ \ |_| | |_| | | (__|   <\__ \ || (_| | |  | |_
/_/   \_\__|_| |_| |_|\___/|___/\__\_\\__,_|_|\___|_|\_\___/\__\__,_|_|   \__|

EOF
    echo -e "${NC}"
    echo -e "${WHITE}Version: ${SCRIPT_VERSION}${NC}"
    echo -e "${WHITE}Infrastructure Deployment Platform${NC}\n"
}

# Print usage
print_usage() {
    cat << EOF
${WHITE}Usage:${NC}
    $SCRIPT_NAME --tenant <name> --account <name> --environment <name> [OPTIONS]

${WHITE}Required Parameters:${NC}
    --tenant, -t        Tenant name (e.g., 'fnx', 'acme')
    --account, -a       Account name (e.g., 'dev', 'staging', 'prod')
    --environment, -e   Environment name (e.g., 'testenv-01', 'production')

${WHITE}Optional Parameters:${NC}
    --region, -r        AWS region (default: ${DEFAULT_REGION})
    --profile, -p       AWS CLI profile to use
    --skip-backend      Skip backend creation (use existing)
    --skip-validation   Skip pre-deployment validation
    --plan-only         Generate plans only, don't apply
    --auto-approve      Auto-approve all changes (DANGEROUS)
    --dry-run           Show what would be done without making changes
    --verbose, -v       Enable verbose output
    --help, -h          Show this help message

${WHITE}Examples:${NC}
    # Deploy development environment
    $SCRIPT_NAME --tenant fnx --account dev --environment testenv-01

    # Deploy production environment with specific profile
    $SCRIPT_NAME --tenant fnx --account prod --environment production --profile prod-admin

    # Plan only (no changes)
    $SCRIPT_NAME --tenant fnx --account dev --environment testenv-01 --plan-only

    # Dry run to see what would happen
    $SCRIPT_NAME --tenant fnx --account dev --environment testenv-01 --dry-run

${WHITE}Environment Variables:${NC}
    AWS_ACCOUNT_ID              Override AWS account ID
    AWS_PROFILE                 AWS CLI profile (overridden by --profile)
    AWS_REGION                  AWS region (overridden by --region)
    ATMOS_TERRAFORM_VERSION     Override Terraform version
    ATMOS_CLI_VERSION           Override Atmos version

${WHITE}For more information:${NC}
    See docs/DEPLOYMENT_GUIDE.md
EOF
}

# Parse command line arguments
parse_args() {
    TENANT=""
    ACCOUNT=""
    ENVIRONMENT=""
    REGION="${AWS_REGION:-$DEFAULT_REGION}"
    AWS_PROFILE_ARG=""
    SKIP_BACKEND=false
    SKIP_VALIDATION=false
    PLAN_ONLY=false
    AUTO_APPROVE=false
    DRY_RUN=false
    VERBOSE=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --tenant|-t)
                TENANT="$2"
                shift 2
                ;;
            --account|-a)
                ACCOUNT="$2"
                shift 2
                ;;
            --environment|-e)
                ENVIRONMENT="$2"
                shift 2
                ;;
            --region|-r)
                REGION="$2"
                shift 2
                ;;
            --profile|-p)
                AWS_PROFILE_ARG="$2"
                shift 2
                ;;
            --skip-backend)
                SKIP_BACKEND=true
                shift
                ;;
            --skip-validation)
                SKIP_VALIDATION=true
                shift
                ;;
            --plan-only)
                PLAN_ONLY=true
                shift
                ;;
            --auto-approve)
                AUTO_APPROVE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --help|-h)
                print_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done

    # Set AWS profile if provided
    if [[ -n "$AWS_PROFILE_ARG" ]]; then
        export AWS_PROFILE="$AWS_PROFILE_ARG"
    fi

    # Export region
    export AWS_DEFAULT_REGION="$REGION"
    export AWS_REGION="$REGION"

    # Validate required parameters
    local missing_params=()
    [[ -z "$TENANT" ]] && missing_params+=("--tenant")
    [[ -z "$ACCOUNT" ]] && missing_params+=("--account")
    [[ -z "$ENVIRONMENT" ]] && missing_params+=("--environment")

    if [[ ${#missing_params[@]} -gt 0 ]]; then
        log_error "Missing required parameters: ${missing_params[*]}"
        echo
        print_usage
        exit 1
    fi

    # Construct stack name
    STACK_NAME="${TENANT}-${ACCOUNT}-${ENVIRONMENT}"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Version comparison function
version_ge() {
    # Returns 0 if $1 >= $2
    printf '%s\n%s' "$2" "$1" | sort -V -C
}

# Check prerequisites
check_prerequisites() {
    log_step "Checking Prerequisites"

    local errors=0
    local warnings=0

    # Check AWS CLI
    echo -n "Checking AWS CLI... "
    if command_exists aws; then
        local aws_version
        aws_version=$(aws --version 2>&1 | cut -d' ' -f1 | cut -d'/' -f2)
        echo -e "${GREEN}OK${NC} (version: $aws_version)"
    else
        echo -e "${RED}NOT FOUND${NC}"
        log_error "AWS CLI is required. Install from: https://aws.amazon.com/cli/"
        ((errors++))
    fi

    # Check Terraform
    echo -n "Checking Terraform... "
    if command_exists terraform; then
        local tf_version
        tf_version=$(terraform version -json 2>/dev/null | jq -r '.terraform_version' 2>/dev/null || terraform version | head -1 | cut -d' ' -f2 | tr -d 'v')
        if version_ge "$tf_version" "$DEFAULT_TERRAFORM_VERSION"; then
            echo -e "${GREEN}OK${NC} (version: $tf_version)"
        else
            echo -e "${YELLOW}WARNING${NC} (version: $tf_version, recommended: >= $DEFAULT_TERRAFORM_VERSION)"
            ((warnings++))
        fi
    else
        echo -e "${RED}NOT FOUND${NC}"
        log_error "Terraform is required. Install from: https://www.terraform.io/downloads.html"
        ((errors++))
    fi

    # Check Atmos
    echo -n "Checking Atmos... "
    if command_exists atmos; then
        local atmos_version
        atmos_version=$(atmos version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
        echo -e "${GREEN}OK${NC} (version: $atmos_version)"
    else
        echo -e "${RED}NOT FOUND${NC}"
        log_error "Atmos is required. Install from: https://atmos.tools/install"
        ((errors++))
    fi

    # Check jq
    echo -n "Checking jq... "
    if command_exists jq; then
        local jq_version
        jq_version=$(jq --version 2>/dev/null | tr -d 'jq-' || echo "unknown")
        echo -e "${GREEN}OK${NC} (version: $jq_version)"
    else
        echo -e "${YELLOW}WARNING${NC} - jq is recommended for JSON processing"
        ((warnings++))
    fi

    # Check Git
    echo -n "Checking Git... "
    if command_exists git; then
        local git_version
        git_version=$(git --version | cut -d' ' -f3)
        echo -e "${GREEN}OK${NC} (version: $git_version)"
    else
        echo -e "${YELLOW}WARNING${NC} - Git is recommended"
        ((warnings++))
    fi

    # Check kubectl (optional for EKS)
    echo -n "Checking kubectl... "
    if command_exists kubectl; then
        local kubectl_version
        kubectl_version=$(kubectl version --client -o json 2>/dev/null | jq -r '.clientVersion.gitVersion' 2>/dev/null || echo "unknown")
        echo -e "${GREEN}OK${NC} (version: $kubectl_version)"
    else
        echo -e "${YELLOW}OPTIONAL${NC} - kubectl is needed for EKS management"
    fi

    # Check Helm (optional for EKS addons)
    echo -n "Checking Helm... "
    if command_exists helm; then
        local helm_version
        helm_version=$(helm version --short 2>/dev/null | tr -d 'v' || echo "unknown")
        echo -e "${GREEN}OK${NC} (version: $helm_version)"
    else
        echo -e "${YELLOW}OPTIONAL${NC} - Helm is needed for Kubernetes addons"
    fi

    echo
    if [[ $errors -gt 0 ]]; then
        log_error "Found $errors missing prerequisite(s). Please install required tools."
        exit 1
    fi

    if [[ $warnings -gt 0 ]]; then
        log_warning "Found $warnings warning(s). Consider updating tools for best results."
    fi

    log_success "All required prerequisites are installed"
}

# Validate AWS credentials
validate_aws_credentials() {
    log_step "Validating AWS Credentials"

    echo -n "Checking AWS credentials... "
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        echo -e "${RED}FAILED${NC}"
        log_error "Invalid or missing AWS credentials"
        echo
        echo "Please configure AWS credentials using one of these methods:"
        echo "  1. aws configure"
        echo "  2. Export AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY"
        echo "  3. Use --profile flag with a configured profile"
        exit 1
    fi
    echo -e "${GREEN}OK${NC}"

    # Get caller identity
    local identity
    identity=$(aws sts get-caller-identity)

    local caller_arn
    local caller_account
    local caller_user
    caller_arn=$(echo "$identity" | jq -r '.Arn')
    caller_account=$(echo "$identity" | jq -r '.Account')
    caller_user=$(echo "$identity" | jq -r '.UserId')

    echo
    echo "AWS Identity:"
    echo "  Account:  $caller_account"
    echo "  ARN:      $caller_arn"
    echo "  Region:   $REGION"
    if [[ -n "${AWS_PROFILE:-}" ]]; then
        echo "  Profile:  $AWS_PROFILE"
    fi

    # Export account ID for Atmos
    export AWS_ACCOUNT_ID="$caller_account"

    # Verify basic permissions
    echo
    echo -n "Checking S3 permissions... "
    if aws s3 ls >/dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${YELLOW}LIMITED${NC} - Some operations may fail"
    fi

    echo -n "Checking EC2 permissions... "
    if aws ec2 describe-regions --region "$REGION" >/dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${YELLOW}LIMITED${NC} - Some operations may fail"
    fi

    echo -n "Checking IAM permissions... "
    if aws iam get-user >/dev/null 2>&1 || aws iam list-roles --max-items 1 >/dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${YELLOW}LIMITED${NC} - Some operations may fail"
    fi

    log_success "AWS credentials validated"
}

# Check if stack exists
check_stack_exists() {
    log_step "Checking Stack Configuration"

    local stack_path="$PROJECT_ROOT/stacks/orgs/$TENANT/$ACCOUNT"

    echo "Looking for stack configuration..."
    echo "  Expected path: $stack_path"
    echo "  Stack name: $STACK_NAME"
    echo

    # Check if stack directory exists
    if [[ ! -d "$stack_path" ]]; then
        log_warning "Stack directory not found: $stack_path"
        echo
        echo "Would you like to create it from a template? [y/N]"

        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[DRY RUN] Would create stack directory"
            return 0
        fi

        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            create_stack_from_template
        else
            log_error "Stack configuration is required. Create it manually or use templates."
            exit 1
        fi
    else
        echo -n "Stack directory exists... "
        echo -e "${GREEN}OK${NC}"
    fi

    # Try to list stacks
    echo -n "Validating stack with Atmos... "
    cd "$PROJECT_ROOT"

    if atmos list stacks 2>/dev/null | grep -q "$STACK_NAME" 2>/dev/null; then
        echo -e "${GREEN}OK${NC}"
        log_success "Stack '$STACK_NAME' found in Atmos configuration"
    else
        echo -e "${YELLOW}WARNING${NC}"
        log_warning "Stack '$STACK_NAME' not found in Atmos. Will attempt to create."
    fi
}

# Create stack from template
create_stack_from_template() {
    log_info "Creating stack configuration from template..."

    local stack_dir="$PROJECT_ROOT/stacks/orgs/$TENANT/$ACCOUNT"
    local env_dir="$stack_dir/$REGION/$ENVIRONMENT"
    local components_dir="$env_dir/components"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] Would create directories:"
        echo "  - $stack_dir"
        echo "  - $env_dir"
        echo "  - $components_dir"
        return 0
    fi

    # Create directory structure
    mkdir -p "$components_dir"

    # Create tenant defaults if not exists
    if [[ ! -f "$PROJECT_ROOT/stacks/orgs/$TENANT/_defaults.yaml" ]]; then
        cat > "$PROJECT_ROOT/stacks/orgs/$TENANT/_defaults.yaml" << EOF
---
vars:
  namespace: $TENANT
  tenant: $TENANT
  management_account_id: "${AWS_ACCOUNT_ID}"  # Update with management account ID
EOF
    fi

    # Create account defaults
    if [[ ! -f "$stack_dir/_defaults.yaml" ]]; then
        cat > "$stack_dir/_defaults.yaml" << EOF
---
import:
  - orgs/$TENANT/_defaults
  - mixins/tenant/$TENANT
  - mixins/stage/$ACCOUNT

vars:
  account: $ACCOUNT
  account_id: "${AWS_ACCOUNT_ID}"
  aws_profile: "$ACCOUNT"
EOF
    fi

    # Create region defaults
    local region_dir="$stack_dir/$REGION"
    mkdir -p "$region_dir"
    if [[ ! -f "$region_dir/_defaults.yaml" ]]; then
        cat > "$region_dir/_defaults.yaml" << EOF
---
vars:
  region: $REGION
EOF
    fi

    # Create main stack file
    cat > "$env_dir.yaml" << EOF
---
# ${ENVIRONMENT} Stack Configuration
# Auto-generated by quickstart.sh on $(date -u '+%Y-%m-%d %H:%M:%S UTC')

import:
  # Import base configuration first
  - catalog/_base/defaults

  # Import mixins (order matters for variable precedence)
  - mixins/tenant/$TENANT
  - mixins/stage/$ACCOUNT
  - mixins/region/$REGION

  # Import org defaults
  - orgs/$TENANT/$ACCOUNT/_defaults

  # Import component-specific configurations
  - orgs/$TENANT/$ACCOUNT/$REGION/$ENVIRONMENT/components/globals
  - orgs/$TENANT/$ACCOUNT/$REGION/$ENVIRONMENT/components/networking
  - orgs/$TENANT/$ACCOUNT/$REGION/$ENVIRONMENT/components/security
  - orgs/$TENANT/$ACCOUNT/$REGION/$ENVIRONMENT/components/compute
  - orgs/$TENANT/$ACCOUNT/$REGION/$ENVIRONMENT/components/services

vars:
  # Core variables for stack naming
  tenant: $TENANT
  environment: $ENVIRONMENT
  stage: $ACCOUNT
  account: $ACCOUNT
  region: $REGION

  # AWS Account ID
  aws_account_id: "${AWS_ACCOUNT_ID}"

  # VPC configuration
  vpc_cidr: "10.0.0.0/16"

  # Description
  description: "${ENVIRONMENT} Environment"
  namespace: $ENVIRONMENT
EOF

    # Create component files
    create_component_files "$components_dir"

    log_success "Stack configuration created at: $env_dir"
}

# Create component configuration files
create_component_files() {
    local dir="$1"

    # Create globals.yaml
    cat > "$dir/globals.yaml" << EOF
---
# Global component configurations for $ENVIRONMENT environment

import:
  - orgs/$TENANT/$ACCOUNT/$REGION/_defaults
  - mixins/development
  - catalog/vpc/defaults
  - catalog/network/defaults
  - catalog/iam/defaults
  - catalog/backend/defaults
  - catalog/monitoring/defaults

metadata:
  description: "${ENVIRONMENT} environment"
  owner: "DevOps Team"
  version: "1.0.0"
  stage: "$ACCOUNT"
  region: "$REGION"

vars:
  environment: $ENVIRONMENT
  tenant_name: $ENVIRONMENT
  domain_name: "example.com"
  hosted_zone_id: "CHANGE_ME"

  # Feature flags
  enable_container_insights: false
  enable_vpc_flow_logs: true
  use_external_secrets: false
  secrets_manager_path_prefix: "$TENANT/certificates"

  # EKS configuration
  eks_kubernetes_version: "1.28"
  eks_public_access: false

tags:
  Team: "DevOps"
  CostCenter: "IT"
  Project: "Infrastructure"
  Environment: "$ENVIRONMENT"
  ManagedBy: "Terraform"
  Tenant: "$TENANT"
EOF

    # Create networking.yaml
    cat > "$dir/networking.yaml" << EOF
---
# Networking component configurations for $ENVIRONMENT environment

import:
  - orgs/$TENANT/$ACCOUNT/$REGION/$ENVIRONMENT/components/globals
  - catalog/vpc/defaults
  - catalog/network/defaults

components:
  terraform:
    vpc/main:
      metadata:
        component: vpc
        inherits:
          - vpc/defaults
      vars:
        name: main
        vpc_cidr: "10.0.0.0/16"
        vpc_flow_logs_enabled: true
        private_subnets:
          - "10.0.1.0/24"
          - "10.0.2.0/24"
          - "10.0.3.0/24"
        public_subnets:
          - "10.0.101.0/24"
          - "10.0.102.0/24"
          - "10.0.103.0/24"
EOF

    # Create security.yaml
    cat > "$dir/security.yaml" << EOF
---
# Security component configurations for $ENVIRONMENT environment

import:
  - orgs/$TENANT/$ACCOUNT/$REGION/$ENVIRONMENT/components/globals
  - catalog/iam/defaults
  - catalog/backend/defaults

components:
  terraform:
    iam/main:
      metadata:
        component: iam
      vars:
        management_account_id: "\${management_account_id}"
        account_id: "${AWS_ACCOUNT_ID}"
        target_account_id: "${AWS_ACCOUNT_ID}"
        cross_account_role_name: "$ENVIRONMENT-$ACCOUNT-$TENANT-CrossAccountRole"
        policy_name: "$ENVIRONMENT-$ACCOUNT-$TENANT-CrossAccountPolicy"

    backend/main:
      metadata:
        component: backend
      vars:
        bucket_name: "$TENANT-terraform-state"
        dynamodb_table_name: "$TENANT-terraform-locks"
        iam_role_name: "$TENANT-terraform-backend-role"
        state_file_key: "\${environment}/\${component}/terraform.tfstate"
EOF

    # Create compute.yaml
    cat > "$dir/compute.yaml" << EOF
---
# Compute component configurations for $ENVIRONMENT environment

import:
  - orgs/$TENANT/$ACCOUNT/$REGION/$ENVIRONMENT/components/globals
  - catalog/eks/defaults
  - catalog/ec2/defaults

components:
  terraform:
    ec2/bastion:
      metadata:
        component: ec2
      vars:
        name: "bastion"
        instance_type: "t3.small"
        vpc_id: "\${output.vpc/main.vpc_id}"
        subnet_id: "\${output.vpc/main.public_subnet_ids[0]}"
        create_ssh_keys: true
        store_ssh_keys_in_secrets_manager: true
        allowed_ingress_rules:
          - from_port: 22
            to_port: 22
            protocol: "tcp"
            cidr_blocks: ["10.0.0.0/8"]
            description: "SSH access from internal networks"
EOF

    # Create services.yaml
    cat > "$dir/services.yaml" << EOF
---
# Services component configurations for $ENVIRONMENT environment

import:
  - orgs/$TENANT/$ACCOUNT/$REGION/$ENVIRONMENT/components/globals
  - catalog/monitoring/defaults

components:
  terraform:
    monitoring/main:
      metadata:
        component: monitoring
      vars:
        enabled: true
        create_dashboard: true
        dashboard_name: "$TENANT-$ENVIRONMENT-dashboard"
        alarm_notifications_enabled: true
        alarm_email_addresses:
          - "ops@example.com"
EOF

    # Create README
    cat > "$dir/README.md" << EOF
# ${ENVIRONMENT} Environment Components

This directory contains the component configurations for the ${ENVIRONMENT} environment.

## Files

- \`globals.yaml\` - Global settings and feature flags
- \`networking.yaml\` - VPC and network resources
- \`security.yaml\` - IAM, secrets, and security configurations
- \`compute.yaml\` - EC2, EKS, and compute resources
- \`services.yaml\` - API Gateway, monitoring, and services

## Deployment Order

1. Backend (Terraform state)
2. VPC and networking
3. IAM and security
4. Compute resources
5. Services and monitoring

## Quick Commands

\`\`\`bash
# Validate all components
atmos validate stacks

# Plan entire environment
atmos workflow plan-environment tenant=$TENANT account=$ACCOUNT environment=$ENVIRONMENT

# Apply entire environment
atmos workflow apply-environment tenant=$TENANT account=$ACCOUNT environment=$ENVIRONMENT auto_approve=true
\`\`\`
EOF
}

# Setup backend infrastructure
setup_backend() {
    log_step "Setting Up Backend Infrastructure"

    if [[ "$SKIP_BACKEND" == "true" ]]; then
        log_info "Skipping backend setup (--skip-backend flag set)"
        return 0
    fi

    local bucket_name="${TENANT}-${ACCOUNT}-${ENVIRONMENT}-terraform-state"
    local dynamodb_table="${TENANT}-${ACCOUNT}-${ENVIRONMENT}-terraform-locks"

    echo "Backend Configuration:"
    echo "  S3 Bucket:      $bucket_name"
    echo "  DynamoDB Table: $dynamodb_table"
    echo "  Region:         $REGION"
    echo

    # Check if bucket exists
    echo -n "Checking if S3 bucket exists... "
    if aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null; then
        echo -e "${GREEN}EXISTS${NC}"
        log_info "Backend bucket already exists. Skipping creation."
    else
        echo -e "${YELLOW}NOT FOUND${NC}"

        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[DRY RUN] Would create S3 bucket: $bucket_name"
        else
            log_info "Creating S3 bucket: $bucket_name"

            # Create bucket with region-appropriate configuration
            if [[ "$REGION" == "us-east-1" ]]; then
                aws s3api create-bucket \
                    --bucket "$bucket_name" \
                    --region "$REGION"
            else
                aws s3api create-bucket \
                    --bucket "$bucket_name" \
                    --region "$REGION" \
                    --create-bucket-configuration LocationConstraint="$REGION"
            fi

            # Enable versioning
            aws s3api put-bucket-versioning \
                --bucket "$bucket_name" \
                --versioning-configuration Status=Enabled

            # Enable encryption
            aws s3api put-bucket-encryption \
                --bucket "$bucket_name" \
                --server-side-encryption-configuration '{
                    "Rules": [{
                        "ApplyServerSideEncryptionByDefault": {
                            "SSEAlgorithm": "AES256"
                        },
                        "BucketKeyEnabled": true
                    }]
                }'

            # Block public access
            aws s3api put-public-access-block \
                --bucket "$bucket_name" \
                --public-access-block-configuration '{
                    "BlockPublicAcls": true,
                    "IgnorePublicAcls": true,
                    "BlockPublicPolicy": true,
                    "RestrictPublicBuckets": true
                }'

            log_success "S3 bucket created and configured"
        fi
    fi

    # Check if DynamoDB table exists
    echo -n "Checking if DynamoDB table exists... "
    if aws dynamodb describe-table --table-name "$dynamodb_table" --region "$REGION" >/dev/null 2>&1; then
        echo -e "${GREEN}EXISTS${NC}"
        log_info "DynamoDB table already exists. Skipping creation."
    else
        echo -e "${YELLOW}NOT FOUND${NC}"

        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[DRY RUN] Would create DynamoDB table: $dynamodb_table"
        else
            log_info "Creating DynamoDB table: $dynamodb_table"

            aws dynamodb create-table \
                --table-name "$dynamodb_table" \
                --attribute-definitions AttributeName=LockID,AttributeType=S \
                --key-schema AttributeName=LockID,KeyType=HASH \
                --billing-mode PAY_PER_REQUEST \
                --region "$REGION" \
                --tags Key=ManagedBy,Value=atmos-quickstart Key=Tenant,Value="$TENANT" Key=Environment,Value="$ENVIRONMENT"

            # Wait for table to be active
            log_info "Waiting for DynamoDB table to become active..."
            aws dynamodb wait table-exists --table-name "$dynamodb_table" --region "$REGION"

            # Enable point-in-time recovery
            aws dynamodb update-continuous-backups \
                --table-name "$dynamodb_table" \
                --region "$REGION" \
                --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true

            log_success "DynamoDB table created and configured"
        fi
    fi

    log_success "Backend infrastructure ready"
}

# Validate configurations
validate_configurations() {
    log_step "Validating Configurations"

    if [[ "$SKIP_VALIDATION" == "true" ]]; then
        log_info "Skipping validation (--skip-validation flag set)"
        return 0
    fi

    cd "$PROJECT_ROOT"

    # Run Terraform format check
    echo -n "Checking Terraform formatting... "
    if terraform fmt -check -recursive ./components/terraform >/dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${YELLOW}WARNING${NC}"
        log_warning "Some Terraform files need formatting. Run: terraform fmt -recursive ./components/terraform"
    fi

    # Validate stacks
    echo -n "Validating Atmos stacks... "
    if atmos validate stacks >/dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${YELLOW}WARNING${NC}"
        log_warning "Stack validation warnings detected. Check with: atmos validate stacks"
    fi

    # List components for the stack
    echo
    echo "Components in stack '$STACK_NAME':"
    if atmos list components -s "$STACK_NAME" 2>/dev/null; then
        echo
    else
        log_warning "Could not list components for stack: $STACK_NAME"
    fi

    log_success "Validation complete"
}

# Deploy infrastructure
deploy_infrastructure() {
    log_step "Deploying Infrastructure"

    cd "$PROJECT_ROOT"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] Would deploy stack: $STACK_NAME"
        echo "[DRY RUN] Components would be deployed in dependency order"
        return 0
    fi

    if [[ "$PLAN_ONLY" == "true" ]]; then
        log_info "Generating deployment plan (--plan-only mode)"

        # Run plan workflow
        atmos workflow plan-environment -f plan-environment.yaml \
            tenant="$TENANT" \
            account="$ACCOUNT" \
            environment="$ENVIRONMENT"

        log_success "Plans generated. Review and run with --auto-approve to apply."
        return 0
    fi

    # Confirm deployment
    if [[ "$AUTO_APPROVE" != "true" ]]; then
        echo
        echo -e "${YELLOW}WARNING: This will deploy infrastructure to AWS.${NC}"
        echo "Stack: $STACK_NAME"
        echo "Region: $REGION"
        echo "Account: ${AWS_ACCOUNT_ID}"
        echo
        echo -n "Do you want to continue? [y/N] "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled by user"
            exit 0
        fi
    fi

    # Run apply workflow
    log_info "Starting infrastructure deployment..."

    local apply_args="tenant=$TENANT account=$ACCOUNT environment=$ENVIRONMENT"
    if [[ "$AUTO_APPROVE" == "true" ]]; then
        apply_args="$apply_args auto_approve=true"
    fi

    if atmos workflow apply -f apply-environment.yaml $apply_args; then
        log_success "Infrastructure deployment completed"
    else
        log_error "Infrastructure deployment failed"
        exit 1
    fi
}

# Run health checks
run_health_checks() {
    log_step "Running Health Checks"

    if [[ "$DRY_RUN" == "true" ]] || [[ "$PLAN_ONLY" == "true" ]]; then
        log_info "Skipping health checks (dry-run or plan-only mode)"
        return 0
    fi

    cd "$PROJECT_ROOT"

    echo "Checking deployed resources..."
    echo

    # Check VPC
    echo -n "VPC status... "
    local vpc_count
    vpc_count=$(aws ec2 describe-vpcs --filters "Name=tag:Tenant,Values=$TENANT" "Name=tag:Environment,Values=$ENVIRONMENT" --query 'Vpcs | length(@)' --output text 2>/dev/null || echo "0")
    if [[ "$vpc_count" -gt 0 ]]; then
        echo -e "${GREEN}OK${NC} ($vpc_count VPC(s) found)"
    else
        echo -e "${YELLOW}NO RESOURCES${NC}"
    fi

    # Check subnets
    echo -n "Subnets status... "
    local subnet_count
    subnet_count=$(aws ec2 describe-subnets --filters "Name=tag:Tenant,Values=$TENANT" "Name=tag:Environment,Values=$ENVIRONMENT" --query 'Subnets | length(@)' --output text 2>/dev/null || echo "0")
    if [[ "$subnet_count" -gt 0 ]]; then
        echo -e "${GREEN}OK${NC} ($subnet_count subnet(s) found)"
    else
        echo -e "${YELLOW}NO RESOURCES${NC}"
    fi

    # Check security groups
    echo -n "Security groups status... "
    local sg_count
    sg_count=$(aws ec2 describe-security-groups --filters "Name=tag:Tenant,Values=$TENANT" "Name=tag:Environment,Values=$ENVIRONMENT" --query 'SecurityGroups | length(@)' --output text 2>/dev/null || echo "0")
    if [[ "$sg_count" -gt 0 ]]; then
        echo -e "${GREEN}OK${NC} ($sg_count security group(s) found)"
    else
        echo -e "${YELLOW}NO RESOURCES${NC}"
    fi

    # Check EC2 instances
    echo -n "EC2 instances status... "
    local ec2_count
    ec2_count=$(aws ec2 describe-instances --filters "Name=tag:Tenant,Values=$TENANT" "Name=tag:Environment,Values=$ENVIRONMENT" "Name=instance-state-name,Values=running" --query 'Reservations[*].Instances | length(@)' --output text 2>/dev/null || echo "0")
    if [[ "$ec2_count" -gt 0 ]]; then
        echo -e "${GREEN}OK${NC} ($ec2_count running instance(s))"
    else
        echo -e "${YELLOW}NO RUNNING INSTANCES${NC}"
    fi

    # Check EKS clusters
    echo -n "EKS clusters status... "
    local eks_clusters
    eks_clusters=$(aws eks list-clusters --query 'clusters' --output text 2>/dev/null | grep -c "$TENANT" || echo "0")
    if [[ "$eks_clusters" -gt 0 ]]; then
        echo -e "${GREEN}OK${NC} ($eks_clusters cluster(s) found)"
    else
        echo -e "${YELLOW}NO CLUSTERS${NC}"
    fi

    echo
    log_success "Health checks completed"
}

# Print deployment summary
print_summary() {
    log_step "Deployment Summary"

    echo -e "${WHITE}Stack Information:${NC}"
    echo "  Name:        $STACK_NAME"
    echo "  Tenant:      $TENANT"
    echo "  Account:     $ACCOUNT"
    echo "  Environment: $ENVIRONMENT"
    echo "  Region:      $REGION"
    echo "  AWS Account: ${AWS_ACCOUNT_ID}"
    echo

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}Mode: DRY RUN - No changes were made${NC}"
    elif [[ "$PLAN_ONLY" == "true" ]]; then
        echo -e "${YELLOW}Mode: PLAN ONLY - Plans generated, no changes applied${NC}"
    else
        echo -e "${GREEN}Mode: FULL DEPLOYMENT - Changes applied${NC}"
    fi

    echo
    echo -e "${WHITE}Backend Resources:${NC}"
    echo "  S3 Bucket:      ${TENANT}-${ACCOUNT}-${ENVIRONMENT}-terraform-state"
    echo "  DynamoDB Table: ${TENANT}-${ACCOUNT}-${ENVIRONMENT}-terraform-locks"
    echo

    echo -e "${WHITE}Useful Commands:${NC}"
    echo "  # View stack outputs"
    echo "  atmos terraform output vpc/main -s $STACK_NAME"
    echo
    echo "  # Plan changes"
    echo "  atmos workflow plan-environment tenant=$TENANT account=$ACCOUNT environment=$ENVIRONMENT"
    echo
    echo "  # Apply changes"
    echo "  atmos workflow apply-environment tenant=$TENANT account=$ACCOUNT environment=$ENVIRONMENT auto_approve=true"
    echo
    echo "  # Destroy environment"
    echo "  atmos workflow destroy -f destroy-environment.yaml tenant=$TENANT account=$ACCOUNT environment=$ENVIRONMENT"
    echo

    echo -e "${WHITE}Documentation:${NC}"
    echo "  - Deployment Guide:  docs/DEPLOYMENT_GUIDE.md"
    echo "  - Operations Guide:  docs/operations/README.md"
    echo "  - Runbooks:          docs/runbooks/"
    echo

    echo -e "${GREEN}${BOLD}Quickstart completed successfully!${NC}"
}

# Main execution
main() {
    print_banner
    parse_args "$@"

    echo "Starting deployment for: $STACK_NAME"
    echo "Timestamp: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo

    # Run deployment steps
    check_prerequisites
    validate_aws_credentials
    check_stack_exists
    setup_backend
    validate_configurations
    deploy_infrastructure
    run_health_checks
    print_summary
}

# Run main with all arguments
main "$@"
