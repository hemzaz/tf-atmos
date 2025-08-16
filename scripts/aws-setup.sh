#!/usr/bin/env bash
# =============================================================================
# AWS Backend Setup and Initialization Script
# =============================================================================
# This script creates and configures AWS backend infrastructure for Terraform
# state management across multiple tenants and environments.
#
# Features:
# - Automated S3 bucket creation with security best practices
# - DynamoDB table setup for state locking
# - Cross-account role configuration
# - Multi-tenant/multi-environment support
# - Comprehensive validation and error handling
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration and Constants
# =============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly LOG_DIR="$PROJECT_ROOT/logs"
readonly LOG_FILE="$LOG_DIR/aws-setup-$(date +%Y%m%d_%H%M%S).log"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color

# Default configurations
readonly DEFAULT_REGION="us-east-1"
readonly DEFAULT_DYNAMODB_BILLING_MODE="PAY_PER_REQUEST"
readonly DEFAULT_BUCKET_SUFFIX="terraform-state"
readonly DEFAULT_DYNAMODB_SUFFIX="terraform-locks"

# =============================================================================
# Utility Functions
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo -e "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    log "INFO" "$*"
    echo -e "${BLUE}ℹ️  $*${NC}"
}

log_success() {
    log "SUCCESS" "$*"
    echo -e "${GREEN}✅ $*${NC}"
}

log_warning() {
    log "WARNING" "$*"
    echo -e "${YELLOW}⚠️  $*${NC}"
}

log_error() {
    log "ERROR" "$*"
    echo -e "${RED}❌ $*${NC}"
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        log "DEBUG" "$*"
        echo -e "${PURPLE}🐛 $*${NC}"
    fi
}

show_usage() {
    cat << EOF
${WHITE}AWS Backend Setup Script${NC}

${WHITE}USAGE:${NC}
    $0 --tenant TENANT --account ACCOUNT --environment ENVIRONMENT [OPTIONS]

${WHITE}REQUIRED PARAMETERS:${NC}
    --tenant TENANT         Tenant name (e.g., 'fnx')
    --account ACCOUNT       Account name (e.g., 'dev', 'prod')  
    --environment ENV       Environment name (e.g., 'testenv-01')

${WHITE}OPTIONAL PARAMETERS:${NC}
    --region REGION         AWS region (default: $DEFAULT_REGION)
    --bucket-suffix SUFFIX  S3 bucket suffix (default: $DEFAULT_DYNAMODB_SUFFIX)
    --dynamodb-suffix SUF   DynamoDB table suffix (default: $DEFAULT_DYNAMODB_SUFFIX)
    --assume-role ARN       Cross-account IAM role ARN to assume
    --dry-run              Show what would be created without making changes
    --force                Skip confirmation prompts
    --kms-key-id ID        Existing KMS key ID for encryption
    --enable-logging       Enable access logging for S3 buckets
    --debug                Enable debug output

${WHITE}EXAMPLES:${NC}
    # Basic setup for development environment
    $0 --tenant fnx --account dev --environment testenv-01

    # Production setup with custom region and KMS key
    $0 --tenant fnx --account prod --environment production \\
       --region us-west-2 --kms-key-id alias/terraform-state

    # Cross-account setup with role assumption
    $0 --tenant fnx --account prod --environment production \\
       --assume-role arn:aws:iam::123456789012:role/TerraformBackendRole

    # Dry run to see what would be created
    $0 --tenant fnx --account dev --environment testenv-01 --dry-run

${WHITE}ENVIRONMENT VARIABLES:${NC}
    AWS_PROFILE            AWS profile to use
    AWS_REGION             Default AWS region
    DEBUG                  Enable debug mode (true/false)
EOF
}

# =============================================================================
# Validation Functions
# =============================================================================

validate_aws_cli() {
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first:"
        echo "  https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        exit 1
    fi
    
    local aws_version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log_debug "AWS CLI version: $aws_version"
}

validate_aws_credentials() {
    log_info "Validating AWS credentials..."
    
    local caller_identity
    if ! caller_identity=$(aws sts get-caller-identity 2>/dev/null); then
        log_error "Invalid AWS credentials. Please configure your credentials:"
        echo "  aws configure"
        echo "  OR set environment variables: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY"
        echo "  OR use AWS profiles: export AWS_PROFILE=your-profile"
        exit 1
    fi
    
    local account_id=$(echo "$caller_identity" | jq -r '.Account')
    local user_arn=$(echo "$caller_identity" | jq -r '.Arn')
    
    log_success "AWS credentials validated"
    log_info "Account ID: $account_id"
    log_info "User/Role: $user_arn"
    
    echo "$account_id"
}

validate_aws_region() {
    local region="$1"
    
    log_info "Validating AWS region: $region"
    
    if ! aws ec2 describe-regions --region-names "$region" &>/dev/null; then
        log_error "Invalid AWS region: $region"
        log_info "Available regions:"
        aws ec2 describe-regions --query 'Regions[].RegionName' --output table
        exit 1
    fi
    
    log_success "Region $region is valid"
}

validate_parameters() {
    local errors=()
    
    if [[ -z "${TENANT:-}" ]]; then
        errors+=("--tenant is required")
    fi
    
    if [[ -z "${ACCOUNT:-}" ]]; then
        errors+=("--account is required")  
    fi
    
    if [[ -z "${ENVIRONMENT:-}" ]]; then
        errors+=("--environment is required")
    fi
    
    if [[ ${#errors[@]} -gt 0 ]]; then
        log_error "Missing required parameters:"
        for error in "${errors[@]}"; do
            echo "  $error"
        done
        echo
        show_usage
        exit 1
    fi
    
    # Validate parameter formats
    if [[ ! "$TENANT" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]$ ]]; then
        log_error "Tenant name must contain only alphanumeric characters and hyphens"
        exit 1
    fi
    
    if [[ ! "$ACCOUNT" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]$ ]]; then
        log_error "Account name must contain only alphanumeric characters and hyphens"
        exit 1
    fi
    
    if [[ ! "$ENVIRONMENT" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]$ ]]; then
        log_error "Environment name must contain only alphanumeric characters and hyphens"
        exit 1
    fi
}

# =============================================================================
# AWS Resource Management Functions
# =============================================================================

assume_cross_account_role() {
    local role_arn="$1"
    
    log_info "Assuming cross-account role: $role_arn"
    
    local session_name="terraform-backend-setup-$(date +%s)"
    local credentials
    
    if ! credentials=$(aws sts assume-role \
        --role-arn "$role_arn" \
        --role-session-name "$session_name" \
        --duration-seconds 3600 2>/dev/null); then
        log_error "Failed to assume role: $role_arn"
        log_info "Ensure the role exists and you have permission to assume it"
        exit 1
    fi
    
    export AWS_ACCESS_KEY_ID=$(echo "$credentials" | jq -r '.Credentials.AccessKeyId')
    export AWS_SECRET_ACCESS_KEY=$(echo "$credentials" | jq -r '.Credentials.SecretAccessKey') 
    export AWS_SESSION_TOKEN=$(echo "$credentials" | jq -r '.Credentials.SessionToken')
    
    log_success "Successfully assumed role: $role_arn"
    
    # Verify the assumed role
    local new_identity
    new_identity=$(aws sts get-caller-identity)
    log_info "Operating as: $(echo "$new_identity" | jq -r '.Arn')"
}

create_kms_key() {
    local key_description="$1"
    local account_id="$2"
    
    log_info "Creating KMS key for encryption..."
    
    local key_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "Enable IAM root permissions",
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::${account_id}:root"
            },
            "Action": "kms:*",
            "Resource": "*"
        },
        {
            "Sid": "Allow Terraform backend operations",
            "Effect": "Allow",
            "Principal": {
                "AWS": "*"
            },
            "Action": [
                "kms:Encrypt",
                "kms:Decrypt",
                "kms:ReEncrypt*",
                "kms:GenerateDataKey*",
                "kms:DescribeKey"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "kms:ViaService": "s3.${REGION}.amazonaws.com"
                }
            }
        }
    ]
}
EOF
    )
    
    local key_result
    if key_result=$(aws kms create-key \
        --policy "$key_policy" \
        --description "$key_description" \
        --key-usage ENCRYPT_DECRYPT \
        --key-spec SYMMETRIC_DEFAULT \
        --region "$REGION" 2>/dev/null); then
        
        local key_id=$(echo "$key_result" | jq -r '.KeyMetadata.KeyId')
        local key_arn=$(echo "$key_result" | jq -r '.KeyMetadata.Arn')
        
        # Create alias
        local alias_name="alias/${TENANT}-terraform-state-key"
        aws kms create-alias \
            --alias-name "$alias_name" \
            --target-key-id "$key_id" \
            --region "$REGION" 2>/dev/null || true
        
        log_success "Created KMS key: $key_id"
        log_info "Key ARN: $key_arn"
        log_info "Alias: $alias_name"
        
        echo "$key_id"
    else
        log_error "Failed to create KMS key"
        exit 1
    fi
}

create_s3_bucket() {
    local bucket_name="$1"
    local kms_key_id="$2"
    local enable_logging="${3:-true}"
    
    log_info "Creating S3 bucket: $bucket_name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create S3 bucket: $bucket_name"
        return 0
    fi
    
    # Check if bucket already exists
    if aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null; then
        log_warning "Bucket $bucket_name already exists"
        return 0
    fi
    
    # Create bucket with region-specific configuration
    if [[ "$REGION" == "us-east-1" ]]; then
        aws s3api create-bucket --bucket "$bucket_name" --region "$REGION"
    else
        aws s3api create-bucket \
            --bucket "$bucket_name" \
            --region "$REGION" \
            --create-bucket-configuration LocationConstraint="$REGION"
    fi
    
    # Enable versioning
    log_info "Enabling versioning on bucket: $bucket_name"
    aws s3api put-bucket-versioning \
        --bucket "$bucket_name" \
        --versioning-configuration Status=Enabled
    
    # Configure server-side encryption
    log_info "Configuring encryption for bucket: $bucket_name"
    local encryption_config
    if [[ -n "$kms_key_id" ]]; then
        encryption_config='{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "aws:kms",
                    "KMSMasterKeyID": "'$kms_key_id'"
                },
                "BucketKeyEnabled": true
            }]
        }'
    else
        encryption_config='{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }]
        }'
    fi
    
    aws s3api put-bucket-encryption \
        --bucket "$bucket_name" \
        --server-side-encryption-configuration "$encryption_config"
    
    # Block public access
    log_info "Configuring public access block for bucket: $bucket_name"
    aws s3api put-public-access-block \
        --bucket "$bucket_name" \
        --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    
    # Apply bucket policy to enforce HTTPS
    log_info "Applying HTTPS-only bucket policy"
    local bucket_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "DenyInsecureConnections",
            "Effect": "Deny",
            "Principal": "*",
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::${bucket_name}/*",
                "arn:aws:s3:::${bucket_name}"
            ],
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "false"
                }
            }
        }
    ]
}
EOF
    )
    
    aws s3api put-bucket-policy \
        --bucket "$bucket_name" \
        --policy "$bucket_policy"
    
    # Configure lifecycle policy
    log_info "Configuring lifecycle policy for bucket: $bucket_name"
    local lifecycle_config=$(cat << EOF
{
    "Rules": [
        {
            "ID": "terraform-state-lifecycle",
            "Status": "Enabled",
            "NoncurrentVersionTransitions": [
                {
                    "NoncurrentDays": 30,
                    "StorageClass": "STANDARD_IA"
                },
                {
                    "NoncurrentDays": 90,  
                    "StorageClass": "GLACIER"
                }
            ],
            "NoncurrentVersionExpiration": {
                "NoncurrentDays": 365
            }
        }
    ]
}
EOF
    )
    
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "$bucket_name" \
        --lifecycle-configuration "$lifecycle_config"
    
    # Configure access logging if requested
    if [[ "$enable_logging" == "true" ]]; then
        local logs_bucket="${bucket_name}-access-logs"
        create_access_logs_bucket "$logs_bucket"
        
        log_info "Configuring access logging for bucket: $bucket_name"
        aws s3api put-bucket-logging \
            --bucket "$bucket_name" \
            --bucket-logging-status "LoggingEnabled={TargetBucket=${logs_bucket},TargetPrefix=access-logs/}"
    fi
    
    # Add tags
    local tags='[
        {"Key":"Purpose","Value":"TerraformState"},
        {"Key":"Environment","Value":"'$ENVIRONMENT'"},
        {"Key":"Tenant","Value":"'$TENANT'"},
        {"Key":"Account","Value":"'$ACCOUNT'"},
        {"Key":"ManagedBy","Value":"aws-setup-script"},
        {"Key":"CreatedDate","Value":"'$(date -u +%Y-%m-%d)'"}
    ]'
    
    aws s3api put-bucket-tagging \
        --bucket "$bucket_name" \
        --tagging "TagSet=$tags"
    
    log_success "Successfully configured S3 bucket: $bucket_name"
}

create_access_logs_bucket() {
    local logs_bucket="$1"
    
    if aws s3api head-bucket --bucket "$logs_bucket" 2>/dev/null; then
        log_info "Access logs bucket $logs_bucket already exists"
        return 0
    fi
    
    log_info "Creating access logs bucket: $logs_bucket"
    
    # Create logs bucket
    if [[ "$REGION" == "us-east-1" ]]; then
        aws s3api create-bucket --bucket "$logs_bucket" --region "$REGION"
    else
        aws s3api create-bucket \
            --bucket "$logs_bucket" \
            --region "$REGION" \
            --create-bucket-configuration LocationConstraint="$REGION"
    fi
    
    # Set appropriate ACL for log delivery
    aws s3api put-bucket-acl --bucket "$logs_bucket" --acl log-delivery-write
    
    # Block public access
    aws s3api put-public-access-block \
        --bucket "$logs_bucket" \
        --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    
    # Configure lifecycle to clean up logs
    local logs_lifecycle=$(cat << EOF
{
    "Rules": [
        {
            "ID": "access-logs-cleanup",
            "Status": "Enabled",
            "Expiration": {
                "Days": 90
            }
        }
    ]
}
EOF
    )
    
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "$logs_bucket" \
        --lifecycle-configuration "$logs_lifecycle"
}

create_dynamodb_table() {
    local table_name="$1"
    
    log_info "Creating DynamoDB table: $table_name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create DynamoDB table: $table_name"
        return 0
    fi
    
    # Check if table already exists
    if aws dynamodb describe-table --table-name "$table_name" --region "$REGION" 2>/dev/null; then
        log_warning "DynamoDB table $table_name already exists"
        return 0
    fi
    
    # Create table
    aws dynamodb create-table \
        --table-name "$table_name" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode "$DEFAULT_DYNAMODB_BILLING_MODE" \
        --region "$REGION"
    
    # Wait for table to become active
    log_info "Waiting for DynamoDB table to become active..."
    aws dynamodb wait table-exists --table-name "$table_name" --region "$REGION"
    
    # Enable point-in-time recovery
    log_info "Enabling point-in-time recovery for table: $table_name"
    aws dynamodb update-continuous-backups \
        --table-name "$table_name" \
        --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true \
        --region "$REGION"
    
    # Add tags
    local table_arn="arn:aws:dynamodb:${REGION}:$(aws sts get-caller-identity --query Account --output text):table/${table_name}"
    aws dynamodb tag-resource \
        --resource-arn "$table_arn" \
        --tags "Key=Purpose,Value=TerraformStateLocking" \
             "Key=Environment,Value=$ENVIRONMENT" \
             "Key=Tenant,Value=$TENANT" \
             "Key=Account,Value=$ACCOUNT" \
             "Key=ManagedBy,Value=aws-setup-script" \
             "Key=CreatedDate,Value=$(date -u +%Y-%m-%d)"
    
    log_success "Successfully configured DynamoDB table: $table_name"
}

# =============================================================================
# Configuration Generation Functions
# =============================================================================

generate_backend_config() {
    local bucket_name="$1"
    local dynamodb_table="$2"
    local kms_key_id="$3"
    
    log_info "Generating backend configuration..."
    
    local config_dir="$PROJECT_ROOT/backend-configs"
    mkdir -p "$config_dir"
    
    local config_file="$config_dir/${TENANT}-${ACCOUNT}-${ENVIRONMENT}.yaml"
    
    cat > "$config_file" << EOF
# Terraform Backend Configuration
# Generated by aws-setup.sh on $(date -u)
# Tenant: $TENANT | Account: $ACCOUNT | Environment: $ENVIRONMENT

import:
  - catalog/backend

vars:
  # Backend Configuration
  tenant: "$TENANT"
  account: "$ACCOUNT" 
  environment: "$ENVIRONMENT"
  region: "$REGION"
  
  # S3 Configuration
  bucket_name: "$bucket_name"
  state_file_key: "terraform.tfstate"
  
  # DynamoDB Configuration  
  dynamodb_table_name: "$dynamodb_table"
  dynamodb_billing_mode: "$DEFAULT_DYNAMODB_BILLING_MODE"
  
  # Security Configuration
  account_id: "$(aws sts get-caller-identity --query Account --output text)"
EOF

    if [[ -n "$kms_key_id" ]]; then
        cat >> "$config_file" << EOF
  kms_key_id: "$kms_key_id"
EOF
    fi

    if [[ -n "${ASSUME_ROLE_ARN:-}" ]]; then
        cat >> "$config_file" << EOF
  
  # Cross-Account Configuration
  iam_role_arn: "$ASSUME_ROLE_ARN"
EOF
    fi

    cat >> "$config_file" << EOF

  # Operational Configuration
  enable_point_in_time_recovery: true
  enable_deletion_protection: true
  enable_monitoring: true
  enable_access_logging: true
  
  # Tags
  tags:
    Purpose: "TerraformBackend"
    Environment: "$ENVIRONMENT"
    Tenant: "$TENANT" 
    Account: "$ACCOUNT"
    ManagedBy: "aws-setup-script"
    CreatedDate: "$(date -u +%Y-%m-%d)"
EOF

    log_success "Backend configuration saved to: $config_file"
    
    # Generate Terraform backend snippet
    local backend_snippet="$config_dir/${TENANT}-${ACCOUNT}-${ENVIRONMENT}-backend.tf"
    cat > "$backend_snippet" << EOF
# Terraform Backend Configuration Snippet
# Copy this to your Terraform configuration

terraform {
  backend "s3" {
    bucket         = "$bucket_name"
    key            = "terraform.tfstate"
    region         = "$REGION"
    dynamodb_table = "$dynamodb_table"
    encrypt        = true
EOF

    if [[ -n "$kms_key_id" ]]; then
        cat >> "$backend_snippet" << EOF
    kms_key_id     = "$kms_key_id"
EOF
    fi

    if [[ -n "${ASSUME_ROLE_ARN:-}" ]]; then
        cat >> "$backend_snippet" << EOF
    role_arn       = "$ASSUME_ROLE_ARN"
EOF
    fi

    cat >> "$backend_snippet" << EOF
  }
}
EOF

    log_success "Backend snippet saved to: $backend_snippet"
    
    echo "$config_file"
}

# =============================================================================
# Summary and Verification Functions  
# =============================================================================

verify_backend_setup() {
    local bucket_name="$1"
    local dynamodb_table="$2"
    
    log_info "Verifying backend setup..."
    
    local verification_errors=()
    
    # Verify S3 bucket
    if aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null; then
        log_success "S3 bucket verified: $bucket_name"
        
        # Check versioning
        local versioning_status
        versioning_status=$(aws s3api get-bucket-versioning --bucket "$bucket_name" --query 'Status' --output text)
        if [[ "$versioning_status" == "Enabled" ]]; then
            log_success "S3 bucket versioning is enabled"
        else
            verification_errors+=("S3 bucket versioning is not enabled")
        fi
        
        # Check encryption
        if aws s3api get-bucket-encryption --bucket "$bucket_name" &>/dev/null; then
            log_success "S3 bucket encryption is configured"
        else
            verification_errors+=("S3 bucket encryption is not configured")
        fi
    else
        verification_errors+=("S3 bucket does not exist or is not accessible: $bucket_name")
    fi
    
    # Verify DynamoDB table
    if aws dynamodb describe-table --table-name "$dynamodb_table" --region "$REGION" &>/dev/null; then
        log_success "DynamoDB table verified: $dynamodb_table"
        
        # Check point-in-time recovery
        local pitr_status
        pitr_status=$(aws dynamodb describe-continuous-backups \
            --table-name "$dynamodb_table" \
            --region "$REGION" \
            --query 'ContinuousBackupsDescription.PointInTimeRecoveryDescription.PointInTimeRecoveryStatus' \
            --output text 2>/dev/null || echo "DISABLED")
        
        if [[ "$pitr_status" == "ENABLED" ]]; then
            log_success "DynamoDB point-in-time recovery is enabled"
        else
            verification_errors+=("DynamoDB point-in-time recovery is not enabled")
        fi
    else
        verification_errors+=("DynamoDB table does not exist or is not accessible: $dynamodb_table")
    fi
    
    if [[ ${#verification_errors[@]} -eq 0 ]]; then
        log_success "Backend setup verification completed successfully"
        return 0
    else
        log_error "Backend setup verification failed with ${#verification_errors[@]} errors:"
        for error in "${verification_errors[@]}"; do
            log_error "  - $error"
        done
        return 1
    fi
}

show_summary() {
    local bucket_name="$1"
    local dynamodb_table="$2"
    local kms_key_id="$3"
    local config_file="$4"
    
    cat << EOF

${WHITE}==========================================
AWS Backend Setup Summary
==========================================${NC}

${WHITE}Configuration:${NC}
  Tenant:           ${GREEN}$TENANT${NC}
  Account:          ${GREEN}$ACCOUNT${NC}
  Environment:      ${GREEN}$ENVIRONMENT${NC}
  Region:           ${GREEN}$REGION${NC}

${WHITE}Resources Created:${NC}
  S3 Bucket:        ${GREEN}$bucket_name${NC}
  DynamoDB Table:   ${GREEN}$dynamodb_table${NC}
EOF

    if [[ -n "$kms_key_id" ]]; then
        echo -e "  KMS Key:          ${GREEN}$kms_key_id${NC}"
    fi

    if [[ -n "${ASSUME_ROLE_ARN:-}" ]]; then
        echo -e "  Cross-Account:    ${GREEN}$ASSUME_ROLE_ARN${NC}"
    fi

    cat << EOF

${WHITE}Next Steps:${NC}
  1. Review configuration: ${CYAN}$config_file${NC}
  2. Apply backend component: ${CYAN}atmos terraform apply backend -s $TENANT-$ACCOUNT-$ENVIRONMENT${NC}
  3. Initialize other components with backend

${WHITE}Backend Configuration:${NC}
$(cat "$config_file" | head -15 | sed 's/^/  /')

${WHITE}Terraform Backend Block:${NC}
  terraform {
    backend "s3" {
      bucket         = "$bucket_name"
      key            = "terraform.tfstate"
      region         = "$REGION"  
      dynamodb_table = "$dynamodb_table"
      encrypt        = true
EOF

    if [[ -n "$kms_key_id" ]]; then
        echo "      kms_key_id     = \"$kms_key_id\""
    fi

    if [[ -n "${ASSUME_ROLE_ARN:-}" ]]; then
        echo "      role_arn       = \"$ASSUME_ROLE_ARN\""
    fi

    cat << EOF
    }
  }

${GREEN}✅ AWS backend setup completed successfully!${NC}

EOF
}

# =============================================================================
# Main Function
# =============================================================================

main() {
    # Initialize logging
    mkdir -p "$LOG_DIR"
    log_info "AWS Backend Setup Script started"
    log_info "Log file: $LOG_FILE"
    
    # Parse command line arguments
    local TENANT=""
    local ACCOUNT=""
    local ENVIRONMENT=""
    local REGION="$DEFAULT_REGION"
    local BUCKET_SUFFIX="$DEFAULT_BUCKET_SUFFIX"
    local DYNAMODB_SUFFIX="$DEFAULT_DYNAMODB_SUFFIX"
    local ASSUME_ROLE_ARN=""
    local DRY_RUN="false"
    local FORCE="false"
    local KMS_KEY_ID=""
    local ENABLE_LOGGING="true"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
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
            --bucket-suffix)
                BUCKET_SUFFIX="$2"
                shift 2
                ;;
            --dynamodb-suffix)
                DYNAMODB_SUFFIX="$2"
                shift 2
                ;;
            --assume-role)
                ASSUME_ROLE_ARN="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --force)
                FORCE="true"
                shift
                ;;
            --kms-key-id)
                KMS_KEY_ID="$2"
                shift 2
                ;;
            --enable-logging)
                ENABLE_LOGGING="true"
                shift
                ;;
            --debug)
                export DEBUG="true"
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Validate inputs
    validate_parameters
    validate_aws_cli
    
    # Generate resource names
    local bucket_name="${TENANT}-${ACCOUNT}-${ENVIRONMENT}-${BUCKET_SUFFIX}"
    local dynamodb_table="${TENANT}-${ACCOUNT}-${ENVIRONMENT}-${DYNAMODB_SUFFIX}"
    
    log_info "Setting up AWS backend for:"
    log_info "  Tenant: $TENANT"
    log_info "  Account: $ACCOUNT" 
    log_info "  Environment: $ENVIRONMENT"
    log_info "  Region: $REGION"
    log_info "  S3 Bucket: $bucket_name"
    log_info "  DynamoDB Table: $dynamodb_table"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN MODE - No resources will be created"
    fi
    
    # Validate AWS setup
    local aws_account_id
    aws_account_id=$(validate_aws_credentials)
    validate_aws_region "$REGION"
    
    # Assume cross-account role if specified
    if [[ -n "$ASSUME_ROLE_ARN" ]]; then
        assume_cross_account_role "$ASSUME_ROLE_ARN"
        aws_account_id=$(aws sts get-caller-identity --query Account --output text)
    fi
    
    # Confirmation prompt (unless forced or dry run)
    if [[ "$FORCE" != "true" && "$DRY_RUN" != "true" ]]; then
        echo
        log_warning "This will create AWS resources that may incur costs"
        echo -e "  S3 Bucket: ${CYAN}$bucket_name${NC}"
        echo -e "  DynamoDB Table: ${CYAN}$dynamodb_table${NC}"
        echo -e "  Region: ${CYAN}$REGION${NC}"
        echo -e "  Account: ${CYAN}$aws_account_id${NC}"
        echo
        read -p "Continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Setup cancelled by user"
            exit 0
        fi
    fi
    
    # Create KMS key if needed
    local kms_key_id="$KMS_KEY_ID"
    if [[ -z "$kms_key_id" && "$DRY_RUN" != "true" ]]; then
        kms_key_id=$(create_kms_key "Terraform state encryption key for $TENANT-$ACCOUNT-$ENVIRONMENT" "$aws_account_id")
    fi
    
    # Create resources
    create_s3_bucket "$bucket_name" "$kms_key_id" "$ENABLE_LOGGING"
    create_dynamodb_table "$dynamodb_table"
    
    # Generate configuration
    local config_file
    config_file=$(generate_backend_config "$bucket_name" "$dynamodb_table" "$kms_key_id")
    
    # Verify setup (skip for dry run)
    if [[ "$DRY_RUN" != "true" ]]; then
        verify_backend_setup "$bucket_name" "$dynamodb_table"
    fi
    
    # Show summary
    show_summary "$bucket_name" "$dynamodb_table" "$kms_key_id" "$config_file"
    
    log_success "AWS backend setup completed successfully"
}

# =============================================================================
# Script Execution
# =============================================================================

# Ensure script is not being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi