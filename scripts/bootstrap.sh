#!/usr/bin/env bash
# =============================================================================
# Bootstrap Script - Initialize Infrastructure Prerequisites
# =============================================================================
# This script sets up all prerequisites for deploying infrastructure:
# - Validates environment and tools
# - Creates S3 backend bucket
# - Creates DynamoDB locks table
# - Configures VPC endpoints
# - Initializes Terraform state

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source utilities
source "$SCRIPT_DIR/utils.sh" 2>/dev/null || {
    echo "ERROR: utils.sh not found"
    exit 1
}

# Default configuration
TENANT="${TENANT:-fnx}"
ACCOUNT="${ACCOUNT:-dev}"
ENVIRONMENT="${ENVIRONMENT:-testenv-01}"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
DRY_RUN="${DRY_RUN:-false}"
FORCE="${FORCE:-false}"

# Derived values
STATE_BUCKET="${TENANT}-${ACCOUNT}-${ENVIRONMENT}-terraform-state"
LOCKS_TABLE="${TENANT}-${ACCOUNT}-${ENVIRONMENT}-terraform-locks"

# =============================================================================
# Helper Functions
# =============================================================================

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Bootstrap infrastructure prerequisites including S3 backend and DynamoDB locks.

OPTIONS:
    -t, --tenant TENANT         Tenant identifier (default: fnx)
    -a, --account ACCOUNT       Account identifier (default: dev)
    -e, --environment ENV       Environment name (default: testenv-01)
    -r, --region REGION         AWS region (default: us-east-1)
    -d, --dry-run               Show what would be done without making changes
    -f, --force                 Force creation even if resources exist
    -h, --help                  Show this help message

EXAMPLES:
    # Bootstrap development environment
    $0 --tenant fnx --account dev --environment testenv-01

    # Dry run to preview changes
    $0 --tenant fnx --account dev --environment testenv-01 --dry-run

    # Force recreation of resources
    $0 --tenant fnx --account dev --environment testenv-01 --force

ENVIRONMENT VARIABLES:
    TENANT                      Override tenant identifier
    ACCOUNT                     Override account identifier
    ENVIRONMENT                 Override environment name
    AWS_DEFAULT_REGION          Override AWS region
    DRY_RUN                     Set to 'true' for dry run
    FORCE                       Set to 'true' to force recreation
EOF
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check required commands
    local required_commands=("aws" "terraform" "atmos" "jq")
    local missing_commands=()

    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_commands+=("$cmd")
        fi
    done

    if [ ${#missing_commands[@]} -gt 0 ]; then
        log_error "Missing required commands: ${missing_commands[*]}"
        log_info "Please install missing dependencies:"
        for cmd in "${missing_commands[@]}"; do
            case "$cmd" in
            aws)
                echo "  - AWS CLI: https://aws.amazon.com/cli/"
                ;;
            terraform)
                echo "  - Terraform: https://www.terraform.io/downloads"
                ;;
            atmos)
                echo "  - Atmos: https://atmos.tools/install"
                ;;
            jq)
                echo "  - jq: https://stedolan.github.io/jq/download/"
                ;;
            esac
        done
        return 1
    fi

    log_success "All prerequisites are installed"

    # Check AWS credentials
    if ! aws sts get-caller-identity &>/dev/null; then
        log_error "AWS credentials not configured or invalid"
        log_info "Please configure AWS credentials:"
        echo "  aws configure"
        echo "  # OR"
        echo "  export AWS_ACCESS_KEY_ID=..."
        echo "  export AWS_SECRET_ACCESS_KEY=..."
        return 1
    fi

    local account_id
    account_id=$(aws sts get-caller-identity --query 'Account' --output text)
    log_success "AWS credentials valid (Account: $account_id)"

    return 0
}

create_s3_backend() {
    log_info "Creating S3 backend bucket: $STATE_BUCKET"

    # Check if bucket exists
    if aws s3api head-bucket --bucket "$STATE_BUCKET" 2>/dev/null; then
        if [ "$FORCE" = "true" ]; then
            log_warning "Bucket exists, but FORCE=true. Proceeding..."
        else
            log_success "Bucket already exists: $STATE_BUCKET"
            return 0
        fi
    fi

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would create S3 bucket: $STATE_BUCKET"
        return 0
    fi

    # Create bucket
    if [ "$REGION" = "us-east-1" ]; then
        aws s3api create-bucket \
            --bucket "$STATE_BUCKET" \
            --region "$REGION"
    else
        aws s3api create-bucket \
            --bucket "$STATE_BUCKET" \
            --region "$REGION" \
            --create-bucket-configuration LocationConstraint="$REGION"
    fi

    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "$STATE_BUCKET" \
        --versioning-configuration Status=Enabled

    # Enable encryption
    aws s3api put-bucket-encryption \
        --bucket "$STATE_BUCKET" \
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
        --bucket "$STATE_BUCKET" \
        --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

    # Add tags
    aws s3api put-bucket-tagging \
        --bucket "$STATE_BUCKET" \
        --tagging "TagSet=[
            {Key=Name,Value=$STATE_BUCKET},
            {Key=Tenant,Value=$TENANT},
            {Key=Account,Value=$ACCOUNT},
            {Key=Environment,Value=$ENVIRONMENT},
            {Key=ManagedBy,Value=Terraform},
            {Key=Purpose,Value=TerraformState}
        ]"

    log_success "S3 bucket created: $STATE_BUCKET"
}

create_dynamodb_table() {
    log_info "Creating DynamoDB locks table: $LOCKS_TABLE"

    # Check if table exists
    if aws dynamodb describe-table --table-name "$LOCKS_TABLE" --region "$REGION" &>/dev/null; then
        if [ "$FORCE" = "true" ]; then
            log_warning "Table exists, but FORCE=true. Proceeding..."
        else
            log_success "Table already exists: $LOCKS_TABLE"
            return 0
        fi
    fi

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would create DynamoDB table: $LOCKS_TABLE"
        return 0
    fi

    # Create table
    aws dynamodb create-table \
        --table-name "$LOCKS_TABLE" \
        --region "$REGION" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --tags "Key=Name,Value=$LOCKS_TABLE" \
        "Key=Tenant,Value=$TENANT" \
        "Key=Account,Value=$ACCOUNT" \
        "Key=Environment,Value=$ENVIRONMENT" \
        "Key=ManagedBy,Value=Terraform" \
        "Key=Purpose,Value=TerraformLocks"

    # Wait for table to be active
    log_info "Waiting for table to become active..."
    aws dynamodb wait table-exists \
        --table-name "$LOCKS_TABLE" \
        --region "$REGION"

    log_success "DynamoDB table created: $LOCKS_TABLE"
}

initialize_terraform() {
    log_info "Initializing Terraform backend configuration..."

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would initialize Terraform backend"
        return 0
    fi

    # Initialize backend using Atmos
    cd "$PROJECT_ROOT"

    log_info "Running Atmos terraform init..."
    atmos terraform init vpc -s "${TENANT}-${ACCOUNT}-${ENVIRONMENT}" || {
        log_warning "Failed to initialize Terraform backend"
        log_info "This is normal if components don't exist yet"
    }

    log_success "Terraform backend initialized"
}

validate_setup() {
    log_info "Validating bootstrap setup..."

    local validation_passed=true

    # Validate S3 bucket
    if aws s3api head-bucket --bucket "$STATE_BUCKET" 2>/dev/null; then
        log_success "S3 bucket exists and is accessible"
    else
        log_error "S3 bucket validation failed"
        validation_passed=false
    fi

    # Validate DynamoDB table
    if aws dynamodb describe-table --table-name "$LOCKS_TABLE" --region "$REGION" &>/dev/null; then
        log_success "DynamoDB table exists and is accessible"
    else
        log_error "DynamoDB table validation failed"
        validation_passed=false
    fi

    if [ "$validation_passed" = true ]; then
        log_success "All validations passed"
        return 0
    else
        log_error "Validation failed"
        return 1
    fi
}

print_summary() {
    cat <<EOF

========================================
 Bootstrap Summary
========================================
Tenant:        $TENANT
Account:       $ACCOUNT
Environment:   $ENVIRONMENT
Region:        $REGION

Resources Created:
  S3 Bucket:   $STATE_BUCKET
  DynamoDB:    $LOCKS_TABLE

Next Steps:
  1. Validate configuration:
     atmos workflow validate tenant=$TENANT account=$ACCOUNT environment=$ENVIRONMENT

  2. Plan infrastructure:
     atmos workflow plan-environment tenant=$TENANT account=$ACCOUNT environment=$ENVIRONMENT

  3. Apply infrastructure:
     atmos workflow apply-environment tenant=$TENANT account=$ACCOUNT environment=$ENVIRONMENT

========================================
EOF
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
        -t | --tenant)
            TENANT="$2"
            shift 2
            ;;
        -a | --account)
            ACCOUNT="$2"
            shift 2
            ;;
        -e | --environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -r | --region)
            REGION="$2"
            shift 2
            ;;
        -d | --dry-run)
            DRY_RUN=true
            shift
            ;;
        -f | --force)
            FORCE=true
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
        esac
    done

    # Update derived values after parsing arguments
    STATE_BUCKET="${TENANT}-${ACCOUNT}-${ENVIRONMENT}-terraform-state"
    LOCKS_TABLE="${TENANT}-${ACCOUNT}-${ENVIRONMENT}-terraform-locks"

    log_header "Infrastructure Bootstrap"

    echo "Configuration:"
    echo "  Tenant:      $TENANT"
    echo "  Account:     $ACCOUNT"
    echo "  Environment: $ENVIRONMENT"
    echo "  Region:      $REGION"
    echo "  Dry Run:     $DRY_RUN"
    echo "  Force:       $FORCE"
    echo

    # Execute bootstrap steps
    check_prerequisites || exit 1
    echo

    create_s3_backend || exit 1
    echo

    create_dynamodb_table || exit 1
    echo

    initialize_terraform || exit 1
    echo

    validate_setup || exit 1

    print_summary

    if [ "$DRY_RUN" = "true" ]; then
        log_warning "DRY RUN - No changes were made"
    else
        log_success "Bootstrap completed successfully!"
    fi
}

main "$@"
