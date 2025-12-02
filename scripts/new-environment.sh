#!/usr/bin/env bash
#
# new-environment.sh - Environment Bootstrap Script
#
# This script creates a new Atmos environment with all required configuration,
# directory structure, and initial setup for rapid deployment.
#
# Usage:
#   ./scripts/new-environment.sh [options]
#   ./scripts/new-environment.sh --interactive
#
# Examples:
#   ./scripts/new-environment.sh --tenant mycompany --account dev --environment testenv-01 --region us-east-1
#   ./scripts/new-environment.sh --interactive
#   ./scripts/new-environment.sh --tenant mycompany --account prod --environment prod-01 --template microservices-platform
#

set -euo pipefail

# ==============================================================================
# Configuration
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Source utility functions if available
if [[ -f "${SCRIPT_DIR}/utils.sh" ]]; then
    source "${SCRIPT_DIR}/utils.sh"
else
    # Fallback formatting
    BOLD="\033[1m"
    RED="\033[31m"
    GREEN="\033[32m"
    YELLOW="\033[33m"
    BLUE="\033[34m"
    CYAN="\033[36m"
    MAGENTA="\033[35m"
    RESET="\033[0m"
fi

# Default configuration
TENANT=""
ACCOUNT=""
ENVIRONMENT=""
REGION=""
VPC_CIDR=""
TEMPLATE="minimal-stack"
ENV_TYPE="development"
INTERACTIVE="false"
FORCE="false"
SKIP_BACKEND="false"
INITIALIZE_WORKSPACE="true"
DRY_RUN="false"

# Available templates
AVAILABLE_TEMPLATES=(
    "web-application"
    "microservices-platform"
    "data-pipeline"
    "serverless-api"
    "batch-processing"
    "full-stack"
    "minimal-stack"
)

# Region configurations
declare -A REGION_AZS
REGION_AZS["us-east-1"]="us-east-1a,us-east-1b,us-east-1c"
REGION_AZS["us-east-2"]="us-east-2a,us-east-2b,us-east-2c"
REGION_AZS["us-west-1"]="us-west-1a,us-west-1b"
REGION_AZS["us-west-2"]="us-west-2a,us-west-2b,us-west-2c"
REGION_AZS["eu-west-1"]="eu-west-1a,eu-west-1b,eu-west-1c"
REGION_AZS["eu-west-2"]="eu-west-2a,eu-west-2b,eu-west-2c"
REGION_AZS["eu-central-1"]="eu-central-1a,eu-central-1b,eu-central-1c"
REGION_AZS["ap-southeast-1"]="ap-southeast-1a,ap-southeast-1b,ap-southeast-1c"
REGION_AZS["ap-southeast-2"]="ap-southeast-2a,ap-southeast-2b,ap-southeast-2c"
REGION_AZS["ap-northeast-1"]="ap-northeast-1a,ap-northeast-1c,ap-northeast-1d"

# Default CIDR blocks by environment type
declare -A DEFAULT_CIDRS
DEFAULT_CIDRS["development"]="10.0.0.0/16"
DEFAULT_CIDRS["staging"]="10.10.0.0/16"
DEFAULT_CIDRS["production"]="10.20.0.0/16"

# ==============================================================================
# Utility Functions
# ==============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${RESET} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${RESET} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${RESET} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${RESET} $*"
}

log_step() {
    echo -e "\n${BOLD}${CYAN}==> $*${RESET}"
}

show_help() {
    cat << EOF
${BOLD}new-environment.sh - Environment Bootstrap Script${RESET}

Creates a new Atmos environment with directory structure, configuration files,
backend initialization, and Terraform workspace setup.

${BOLD}USAGE:${RESET}
    $0 [options]
    $0 --interactive

${BOLD}REQUIRED OPTIONS:${RESET}
    --tenant <name>           Tenant/organization name (e.g., mycompany)
    --account <name>          Account identifier (e.g., dev, staging, prod)
    --environment <name>      Environment name (e.g., testenv-01, prod-01)
    --region <region>         AWS region (e.g., us-east-1, eu-west-1)

${BOLD}OPTIONAL:${RESET}
    --vpc-cidr <cidr>         VPC CIDR block (default: auto-assigned based on env type)
    --template <name>         Stack template to use (default: minimal-stack)
    --env-type <type>         Environment type: development, staging, production
    --interactive, -i         Interactive mode with prompts
    --force                   Overwrite existing environment
    --skip-backend            Skip backend initialization
    --no-workspace            Don't initialize Terraform workspace
    --dry-run                 Show what would be created without making changes
    --help, -h                Show this help message

${BOLD}AVAILABLE TEMPLATES:${RESET}
    web-application           Web app with VPC, RDS, monitoring
    microservices-platform    EKS-based microservices
    data-pipeline             Lambda-based data processing
    serverless-api            Serverless REST API
    batch-processing          Batch job processing
    full-stack                Complete production infrastructure
    minimal-stack             Basic VPC and security only

${BOLD}EXAMPLES:${RESET}
    # Create development environment interactively
    $0 --interactive

    # Create development environment
    $0 --tenant mycompany --account dev --environment testenv-01 --region us-east-1

    # Create production environment with full stack template
    $0 --tenant mycompany --account prod --environment prod-01 \\
       --region us-east-1 --template full-stack --env-type production

    # Dry run to see what would be created
    $0 --tenant mycompany --account staging --environment stage-01 \\
       --region eu-west-1 --dry-run

${BOLD}DIRECTORY STRUCTURE CREATED:${RESET}
    stacks/orgs/<tenant>/<account>/<environment>/
    +-- main.yaml           # Main stack configuration
    +-- vars.yaml           # Environment variables
    +-- backend.yaml        # Backend configuration

${BOLD}NOTES:${RESET}
    - Environment names should follow pattern: <name>-<number> (e.g., testenv-01)
    - VPC CIDR is auto-assigned if not specified based on environment type
    - Backend state bucket is created if it doesn't exist

EOF
}

# ==============================================================================
# Interactive Mode
# ==============================================================================

prompt_value() {
    local prompt="$1"
    local default="${2:-}"
    local result=""

    if [[ -n "$default" ]]; then
        echo -ne "${BOLD}$prompt${RESET} [${default}]: "
    else
        echo -ne "${BOLD}$prompt${RESET}: "
    fi

    read -r result

    if [[ -z "$result" && -n "$default" ]]; then
        result="$default"
    fi

    echo "$result"
}

prompt_selection() {
    local prompt="$1"
    shift
    local options=("$@")

    echo -e "\n${BOLD}$prompt${RESET}"
    local i=1
    for opt in "${options[@]}"; do
        echo "  $i) $opt"
        ((i++))
    done

    local selection=""
    while [[ -z "$selection" || ! "$selection" =~ ^[0-9]+$ || "$selection" -lt 1 || "$selection" -gt "${#options[@]}" ]]; do
        echo -ne "Select [1-${#options[@]}]: "
        read -r selection
    done

    echo "${options[$((selection-1))]}"
}

run_interactive() {
    echo ""
    echo -e "${BOLD}${CYAN}======================================${RESET}"
    echo -e "${BOLD}${CYAN}  New Environment Setup Wizard       ${RESET}"
    echo -e "${BOLD}${CYAN}======================================${RESET}"
    echo ""

    # Tenant
    TENANT=$(prompt_value "Tenant/Organization name" "${TENANT:-mycompany}")

    # Account
    local account_options=("dev" "staging" "prod" "sandbox" "shared")
    ACCOUNT=$(prompt_selection "Select account type:" "${account_options[@]}")

    # Environment name
    local default_env=""
    case "$ACCOUNT" in
        dev) default_env="testenv-01" ;;
        staging) default_env="stage-01" ;;
        prod) default_env="prod-01" ;;
        sandbox) default_env="sandbox-01" ;;
        shared) default_env="shared-01" ;;
    esac
    ENVIRONMENT=$(prompt_value "Environment name" "$default_env")

    # Region
    local region_options=("us-east-1" "us-east-2" "us-west-2" "eu-west-1" "eu-west-2" "eu-central-1" "ap-southeast-1")
    REGION=$(prompt_selection "Select AWS region:" "${region_options[@]}")

    # Environment type
    local env_type_options=("development" "staging" "production")
    ENV_TYPE=$(prompt_selection "Select environment type:" "${env_type_options[@]}")

    # Template
    TEMPLATE=$(prompt_selection "Select stack template:" "${AVAILABLE_TEMPLATES[@]}")

    # VPC CIDR
    local default_cidr="${DEFAULT_CIDRS[$ENV_TYPE]}"
    VPC_CIDR=$(prompt_value "VPC CIDR block" "$default_cidr")

    # Confirmation
    echo ""
    echo -e "${BOLD}Configuration Summary:${RESET}"
    echo "  Tenant:      $TENANT"
    echo "  Account:     $ACCOUNT"
    echo "  Environment: $ENVIRONMENT"
    echo "  Region:      $REGION"
    echo "  Env Type:    $ENV_TYPE"
    echo "  Template:    $TEMPLATE"
    echo "  VPC CIDR:    $VPC_CIDR"
    echo ""

    local confirm
    echo -ne "Create this environment? (y/n): "
    read -r confirm
    if [[ "$confirm" != "y" ]]; then
        log_info "Environment creation cancelled"
        exit 0
    fi
}

# ==============================================================================
# Validation Functions
# ==============================================================================

validate_inputs() {
    local errors=0

    # Validate tenant
    if [[ -z "$TENANT" ]]; then
        log_error "Tenant name is required"
        ((errors++))
    elif [[ ! "$TENANT" =~ ^[a-z][a-z0-9-]*$ ]]; then
        log_error "Tenant name must start with a letter and contain only lowercase letters, numbers, and hyphens"
        ((errors++))
    fi

    # Validate account
    if [[ -z "$ACCOUNT" ]]; then
        log_error "Account name is required"
        ((errors++))
    elif [[ ! "$ACCOUNT" =~ ^[a-z][a-z0-9-]*$ ]]; then
        log_error "Account name must start with a letter and contain only lowercase letters, numbers, and hyphens"
        ((errors++))
    fi

    # Validate environment
    if [[ -z "$ENVIRONMENT" ]]; then
        log_error "Environment name is required"
        ((errors++))
    elif [[ ! "$ENVIRONMENT" =~ ^[a-z][a-z0-9-]*$ ]]; then
        log_error "Environment name must start with a letter and contain only lowercase letters, numbers, and hyphens"
        ((errors++))
    fi

    # Validate region
    if [[ -z "$REGION" ]]; then
        log_error "Region is required"
        ((errors++))
    elif [[ -z "${REGION_AZS[$REGION]:-}" ]]; then
        log_warning "Unknown region: $REGION - will attempt to auto-detect AZs"
    fi

    # Validate template
    local valid_template="false"
    for t in "${AVAILABLE_TEMPLATES[@]}"; do
        if [[ "$t" == "$TEMPLATE" ]]; then
            valid_template="true"
            break
        fi
    done
    if [[ "$valid_template" != "true" ]]; then
        log_error "Invalid template: $TEMPLATE"
        log_info "Available templates: ${AVAILABLE_TEMPLATES[*]}"
        ((errors++))
    fi

    # Validate or set VPC CIDR
    if [[ -z "$VPC_CIDR" ]]; then
        VPC_CIDR="${DEFAULT_CIDRS[$ENV_TYPE]:-10.0.0.0/16}"
        log_info "Using default VPC CIDR: $VPC_CIDR"
    elif [[ ! "$VPC_CIDR" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        log_error "Invalid VPC CIDR format: $VPC_CIDR"
        ((errors++))
    fi

    if [[ $errors -gt 0 ]]; then
        return 1
    fi

    return 0
}

check_existing_environment() {
    local stack_dir="${REPO_ROOT}/stacks/orgs/${TENANT}/${ACCOUNT}/${ENVIRONMENT}"

    if [[ -d "$stack_dir" ]]; then
        if [[ "$FORCE" == "true" ]]; then
            log_warning "Environment already exists. Force flag set - will overwrite."
            rm -rf "$stack_dir"
        else
            log_error "Environment already exists: $stack_dir"
            log_info "Use --force to overwrite"
            return 1
        fi
    fi

    return 0
}

# ==============================================================================
# Environment Creation
# ==============================================================================

get_availability_zones() {
    local region="$1"

    # Use predefined AZs if available
    if [[ -n "${REGION_AZS[$region]:-}" ]]; then
        echo "${REGION_AZS[$region]}"
        return 0
    fi

    # Try to fetch from AWS
    if command -v aws &> /dev/null; then
        local azs
        azs=$(aws ec2 describe-availability-zones \
            --region "$region" \
            --query 'AvailabilityZones[?State==`available`].ZoneName' \
            --output text 2>/dev/null | tr '\t' ',' | cut -d',' -f1-3)
        if [[ -n "$azs" ]]; then
            echo "$azs"
            return 0
        fi
    fi

    # Fallback to pattern
    echo "${region}a,${region}b,${region}c"
}

create_directory_structure() {
    log_step "Creating Directory Structure"

    local stack_dir="${REPO_ROOT}/stacks/orgs/${TENANT}/${ACCOUNT}/${ENVIRONMENT}"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create directory: $stack_dir"
        return 0
    fi

    mkdir -p "$stack_dir"
    log_success "Created directory: $stack_dir"
}

generate_main_yaml() {
    log_step "Generating Main Stack Configuration"

    local stack_dir="${REPO_ROOT}/stacks/orgs/${TENANT}/${ACCOUNT}/${ENVIRONMENT}"
    local main_file="${stack_dir}/main.yaml"
    local azs=$(get_availability_zones "$REGION")
    local az_array=$(echo "$azs" | tr ',' '\n' | sed 's/^/    - "/' | sed 's/$/"/')

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create: $main_file"
        return 0
    fi

    cat > "$main_file" << EOF
# =============================================================================
# Atmos Stack Configuration
# =============================================================================
# Stack: ${TENANT}-${ACCOUNT}-${ENVIRONMENT}
# Template: ${TEMPLATE}
# Environment Type: ${ENV_TYPE}
# Created: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
# =============================================================================

import:
  # Base configurations
  - catalog/defaults
  - catalog/vpc/defaults
  - catalog/templates/${TEMPLATE}
  # Tenant and environment mixins
  - mixins/tenant/default
  - mixins/region/${REGION}

# Global variables for this stack
vars:
  # Identity
  tenant: "${TENANT}"
  account: "${ACCOUNT}"
  environment: "${ENVIRONMENT}"
  namespace: "${TENANT}"
  stage: "${ACCOUNT}"
  name: "${ENVIRONMENT}"

  # AWS Configuration
  region: "${REGION}"
  availability_zones:
${az_array}

  # Networking
  vpc_cidr: "${VPC_CIDR}"

  # Environment settings
  env_type: "${ENV_TYPE}"
  cost_center: "${ACCOUNT}"

  # Tags
  tags:
    Tenant: "${TENANT}"
    Account: "${ACCOUNT}"
    Environment: "${ENVIRONMENT}"
    Region: "${REGION}"
    ManagedBy: "atmos"
    Template: "${TEMPLATE}"
    CreatedDate: "$(date +%Y-%m-%d)"

# Component configurations
# Customize or override component settings here
components:
  terraform:
    # VPC Component
    vpc:
      vars:
        name: "\${var.tenant}-\${var.account}-\${var.environment}-vpc"
        cidr_block: "\${var.vpc_cidr}"
        enable_dns_hostnames: true
        enable_dns_support: true

    # Security Groups
    securitygroup:
      vars:
        name: "\${var.tenant}-\${var.account}-\${var.environment}-sg"

# Backend configuration
# State is stored in S3 with DynamoDB locking
terraform:
  backend_type: s3
  backend:
    s3:
      encrypt: true
      bucket: "atmos-terraform-state-${TENANT}-${ACCOUNT}"
      key: "terraform/${TENANT}/${ACCOUNT}/${ENVIRONMENT}/\${component}.tfstate"
      dynamodb_table: "atmos-terraform-state-lock"
      region: "${REGION}"
EOF

    log_success "Created: $main_file"
}

generate_vars_yaml() {
    log_step "Generating Variables File"

    local stack_dir="${REPO_ROOT}/stacks/orgs/${TENANT}/${ACCOUNT}/${ENVIRONMENT}"
    local vars_file="${stack_dir}/vars.yaml"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create: $vars_file"
        return 0
    fi

    # Environment-specific variable defaults
    local min_size=1
    local max_size=3
    local desired_size=2
    local instance_type="t3.medium"
    local db_instance_class="db.t3.micro"
    local multi_az="false"

    case "$ENV_TYPE" in
        production)
            min_size=3
            max_size=10
            desired_size=5
            instance_type="m5.large"
            db_instance_class="db.r5.large"
            multi_az="true"
            ;;
        staging)
            min_size=2
            max_size=5
            desired_size=3
            instance_type="t3.large"
            db_instance_class="db.t3.medium"
            multi_az="false"
            ;;
    esac

    cat > "$vars_file" << EOF
# =============================================================================
# Environment Variables
# =============================================================================
# These variables override defaults for this specific environment.
# Customize values here without modifying the main stack configuration.
# =============================================================================

vars:
  # Compute Settings
  compute:
    default_instance_type: "${instance_type}"
    min_size: ${min_size}
    max_size: ${max_size}
    desired_size: ${desired_size}

  # Database Settings
  database:
    instance_class: "${db_instance_class}"
    multi_az: ${multi_az}
    backup_retention_days: $( [[ "$ENV_TYPE" == "production" ]] && echo "30" || echo "7" )
    delete_protection: $( [[ "$ENV_TYPE" == "production" ]] && echo "true" || echo "false" )

  # Networking Settings
  networking:
    single_nat_gateway: $( [[ "$ENV_TYPE" == "production" ]] && echo "false" || echo "true" )
    enable_vpn_gateway: false
    enable_flow_logs: $( [[ "$ENV_TYPE" == "production" ]] && echo "true" || echo "false" )

  # Monitoring Settings
  monitoring:
    enable_detailed_monitoring: $( [[ "$ENV_TYPE" == "production" ]] && echo "true" || echo "false" )
    log_retention_days: $( [[ "$ENV_TYPE" == "production" ]] && echo "90" || echo "30" )
    enable_alerts: true

  # Security Settings
  security:
    enable_encryption: true
    enable_waf: $( [[ "$ENV_TYPE" == "production" ]] && echo "true" || echo "false" )
    ssl_policy: "ELBSecurityPolicy-TLS-1-2-2017-01"

  # Cost Management
  cost:
    enable_spot_instances: $( [[ "$ENV_TYPE" == "production" ]] && echo "false" || echo "true" )
    enable_savings_plans: $( [[ "$ENV_TYPE" == "production" ]] && echo "true" || echo "false" )
EOF

    log_success "Created: $vars_file"
}

generate_backend_yaml() {
    log_step "Generating Backend Configuration"

    local stack_dir="${REPO_ROOT}/stacks/orgs/${TENANT}/${ACCOUNT}/${ENVIRONMENT}"
    local backend_file="${stack_dir}/backend.yaml"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create: $backend_file"
        return 0
    fi

    cat > "$backend_file" << EOF
# =============================================================================
# Terraform Backend Configuration
# =============================================================================
# S3 backend with DynamoDB state locking
# =============================================================================

terraform:
  backend_type: s3
  backend:
    s3:
      # State storage
      bucket: "atmos-terraform-state-${TENANT}-${ACCOUNT}"
      key: "terraform/${TENANT}/${ACCOUNT}/${ENVIRONMENT}/\${component}.tfstate"
      region: "${REGION}"
      encrypt: true

      # State locking
      dynamodb_table: "atmos-terraform-state-lock"

      # Access configuration (uncomment if using cross-account access)
      # role_arn: "arn:aws:iam::ACCOUNT_ID:role/terraform-state-access"

      # Workspace prefix (if using workspaces)
      # workspace_key_prefix: "workspaces"

# Backend initialization notes:
# 1. Ensure S3 bucket exists: atmos-terraform-state-${TENANT}-${ACCOUNT}
# 2. Ensure DynamoDB table exists: atmos-terraform-state-lock
# 3. IAM permissions required:
#    - s3:GetObject, s3:PutObject, s3:DeleteObject on bucket
#    - dynamodb:GetItem, dynamodb:PutItem, dynamodb:DeleteItem on table
EOF

    log_success "Created: $backend_file"
}

initialize_backend() {
    if [[ "$SKIP_BACKEND" == "true" ]]; then
        log_info "Skipping backend initialization (--skip-backend)"
        return 0
    fi

    log_step "Initializing Backend"

    local bucket_name="atmos-terraform-state-${TENANT}-${ACCOUNT}"
    local table_name="atmos-terraform-state-lock"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create S3 bucket: $bucket_name"
        log_info "[DRY-RUN] Would create DynamoDB table: $table_name"
        return 0
    fi

    # Check if bucket exists
    if aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null; then
        log_info "S3 bucket already exists: $bucket_name"
    else
        log_info "Creating S3 bucket: $bucket_name"
        if [[ "$REGION" == "us-east-1" ]]; then
            aws s3api create-bucket --bucket "$bucket_name" --region "$REGION"
        else
            aws s3api create-bucket --bucket "$bucket_name" --region "$REGION" \
                --create-bucket-configuration LocationConstraint="$REGION"
        fi

        # Enable versioning
        aws s3api put-bucket-versioning --bucket "$bucket_name" \
            --versioning-configuration Status=Enabled

        # Enable encryption
        aws s3api put-bucket-encryption --bucket "$bucket_name" \
            --server-side-encryption-configuration '{
                "Rules": [{
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "AES256"
                    }
                }]
            }'

        # Block public access
        aws s3api put-public-access-block --bucket "$bucket_name" \
            --public-access-block-configuration '{
                "BlockPublicAcls": true,
                "IgnorePublicAcls": true,
                "BlockPublicPolicy": true,
                "RestrictPublicBuckets": true
            }'

        log_success "Created S3 bucket: $bucket_name"
    fi

    # Check if DynamoDB table exists
    if aws dynamodb describe-table --table-name "$table_name" --region "$REGION" &>/dev/null; then
        log_info "DynamoDB table already exists: $table_name"
    else
        log_info "Creating DynamoDB table: $table_name"
        aws dynamodb create-table \
            --table-name "$table_name" \
            --attribute-definitions AttributeName=LockID,AttributeType=S \
            --key-schema AttributeName=LockID,KeyType=HASH \
            --billing-mode PAY_PER_REQUEST \
            --region "$REGION"

        # Wait for table to be active
        aws dynamodb wait table-exists --table-name "$table_name" --region "$REGION"

        log_success "Created DynamoDB table: $table_name"
    fi
}

initialize_workspace() {
    if [[ "$INITIALIZE_WORKSPACE" != "true" ]]; then
        log_info "Skipping workspace initialization (--no-workspace)"
        return 0
    fi

    log_step "Initializing Terraform Workspace"

    local stack_name="${TENANT}-${ACCOUNT}-${ENVIRONMENT}"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would initialize Terraform for stack: $stack_name"
        return 0
    fi

    # Try to initialize with Atmos
    log_info "Running Atmos terraform init for VPC component..."
    if atmos terraform init vpc -s "$stack_name" 2>/dev/null; then
        log_success "Terraform initialized for stack: $stack_name"
    else
        log_warning "Could not initialize Terraform automatically"
        log_info "Run manually: atmos terraform init vpc -s $stack_name"
    fi
}

add_to_catalog() {
    log_step "Updating Catalog References"

    local tenant_mixin="${REPO_ROOT}/stacks/mixins/tenant/${TENANT}.yaml"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would update catalog references"
        return 0
    fi

    # Create tenant mixin if it doesn't exist
    if [[ ! -f "$tenant_mixin" ]]; then
        mkdir -p "$(dirname "$tenant_mixin")"
        cat > "$tenant_mixin" << EOF
# Tenant configuration: ${TENANT}
vars:
  tenant: "${TENANT}"
  organization: "${TENANT}"
EOF
        log_success "Created tenant mixin: $tenant_mixin"
    else
        log_info "Tenant mixin already exists: $tenant_mixin"
    fi
}

# ==============================================================================
# Summary and Next Steps
# ==============================================================================

show_summary() {
    log_step "Environment Created Successfully"

    local stack_name="${TENANT}-${ACCOUNT}-${ENVIRONMENT}"
    local stack_dir="${REPO_ROOT}/stacks/orgs/${TENANT}/${ACCOUNT}/${ENVIRONMENT}"

    echo ""
    echo -e "${BOLD}Stack Details:${RESET}"
    echo "  Stack Name:     $stack_name"
    echo "  Directory:      $stack_dir"
    echo "  Template:       $TEMPLATE"
    echo "  Environment:    $ENV_TYPE"
    echo "  Region:         $REGION"
    echo "  VPC CIDR:       $VPC_CIDR"
    echo ""

    echo -e "${BOLD}Files Created:${RESET}"
    if [[ "$DRY_RUN" != "true" ]]; then
        ls -la "$stack_dir/"
    fi
    echo ""

    echo -e "${BOLD}Next Steps:${RESET}"
    echo ""
    echo "  1. Review and customize the configuration:"
    echo "     ${CYAN}cat $stack_dir/main.yaml${RESET}"
    echo ""
    echo "  2. Validate the stack:"
    echo "     ${CYAN}atmos validate stacks${RESET}"
    echo ""
    echo "  3. Plan the deployment:"
    echo "     ${CYAN}atmos terraform plan vpc -s $stack_name${RESET}"
    echo ""
    echo "  4. Deploy the environment:"
    echo "     ${CYAN}./scripts/deploy-stack.sh --template $TEMPLATE --stack $stack_name${RESET}"
    echo ""
    echo "  Or deploy step by step:"
    echo "     ${CYAN}atmos terraform apply vpc -s $stack_name${RESET}"
    echo "     ${CYAN}atmos terraform apply securitygroup -s $stack_name${RESET}"
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}This was a dry run. No files were created.${RESET}"
        echo "Remove --dry-run to create the environment."
    fi
}

# ==============================================================================
# Argument Parsing
# ==============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --tenant)
                TENANT="$2"
                shift 2
                ;;
            --account)
                ACCOUNT="$2"
                shift 2
                ;;
            --environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            --region)
                REGION="$2"
                shift 2
                ;;
            --vpc-cidr)
                VPC_CIDR="$2"
                shift 2
                ;;
            --template)
                TEMPLATE="$2"
                shift 2
                ;;
            --env-type)
                ENV_TYPE="$2"
                shift 2
                ;;
            --interactive|-i)
                INTERACTIVE="true"
                shift
                ;;
            --force)
                FORCE="true"
                shift
                ;;
            --skip-backend)
                SKIP_BACKEND="true"
                shift
                ;;
            --no-workspace)
                INITIALIZE_WORKSPACE="false"
                shift
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# ==============================================================================
# Main Execution
# ==============================================================================

main() {
    parse_args "$@"

    echo ""
    echo -e "${BOLD}${CYAN}======================================${RESET}"
    echo -e "${BOLD}${CYAN}  Atmos Environment Bootstrap        ${RESET}"
    echo -e "${BOLD}${CYAN}======================================${RESET}"
    echo ""

    # Run interactive mode if requested or if required args missing
    if [[ "$INTERACTIVE" == "true" ]] || [[ -z "$TENANT" && -z "$ACCOUNT" && -z "$ENVIRONMENT" && -z "$REGION" ]]; then
        run_interactive
    fi

    # Validate inputs
    if ! validate_inputs; then
        exit 1
    fi

    # Check for existing environment
    if ! check_existing_environment; then
        exit 1
    fi

    # Create environment
    create_directory_structure
    generate_main_yaml
    generate_vars_yaml
    generate_backend_yaml
    initialize_backend
    add_to_catalog
    initialize_workspace

    # Show summary
    show_summary

    exit 0
}

# Run main function
main "$@"
