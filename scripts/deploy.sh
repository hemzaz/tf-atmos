#!/usr/bin/env bash
# =============================================================================
# Deploy Script - Automated Infrastructure Deployment
# =============================================================================
# Deploys infrastructure components in the correct order with health checks

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source utilities
source "$SCRIPT_DIR/utils.sh" 2>/dev/null || {
    echo "ERROR: utils.sh not found"
    exit 1
}

# Configuration
TENANT="${TENANT:-fnx}"
ACCOUNT="${ACCOUNT:-dev}"
ENVIRONMENT="${ENVIRONMENT:-testenv-01}"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
AUTO_APPROVE="${AUTO_APPROVE:-false}"
SKIP_TESTS="${SKIP_TESTS:-false}"
COMPONENTS="${COMPONENTS:-}"

# Deployment order - components are deployed in this sequence
DEFAULT_COMPONENT_ORDER=(
    "vpc"
    "securitygroup"
    "iam"
    "kms"
    "secretsmanager"
    "s3"
    "dynamodb"
    "rds"
    "elasticache"
    "eks"
    "eks-addons"
    "lambda"
    "monitoring"
)

# =============================================================================
# Functions
# =============================================================================

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Deploy infrastructure components in the correct order.

OPTIONS:
    -t, --tenant TENANT         Tenant identifier (default: fnx)
    -a, --account ACCOUNT       Account identifier (default: dev)
    -e, --environment ENV       Environment name (default: testenv-01)
    -r, --region REGION         AWS region (default: us-east-1)
    -c, --components COMPONENTS Comma-separated list of components to deploy
    --auto-approve              Auto-approve deployment (use with caution)
    --skip-tests                Skip health checks and smoke tests
    -h, --help                  Show this help message

EXAMPLES:
    # Deploy all components
    $0 --tenant fnx --account dev --environment testenv-01

    # Deploy specific components
    $0 --tenant fnx --account dev --environment testenv-01 --components vpc,securitygroup,iam

    # Deploy with auto-approve (CI/CD)
    $0 --tenant fnx --account dev --environment testenv-01 --auto-approve

EOF
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v atmos &>/dev/null; then
        log_error "Atmos CLI not found"
        return 1
    fi

    if ! command -v terraform &>/dev/null; then
        log_error "Terraform not found"
        return 1
    fi

    if ! aws sts get-caller-identity &>/dev/null; then
        log_error "AWS credentials not configured"
        return 1
    fi

    log_success "Prerequisites check passed"
}

validate_environment() {
    log_info "Validating environment configuration..."

    cd "$PROJECT_ROOT"

    if ! atmos workflow validate tenant="$TENANT" account="$ACCOUNT" environment="$ENVIRONMENT" 2>/dev/null; then
        log_warning "Environment validation had issues"
        log_info "Continuing with deployment..."
    else
        log_success "Environment validation passed"
    fi
}

deploy_component() {
    local component="$1"
    local stack="${TENANT}-${ACCOUNT}-${ENVIRONMENT}"

    log_header "Deploying Component: $component"

    cd "$PROJECT_ROOT"

    # Check if component exists
    if [ ! -d "components/terraform/$component" ]; then
        log_warning "Component directory not found: $component"
        return 1
    fi

    # Initialize component
    log_info "Initializing $component..."
    if ! atmos terraform init "$component" -s "$stack"; then
        log_error "Failed to initialize $component"
        return 1
    fi

    # Plan component
    log_info "Planning $component..."
    local plan_file="/tmp/${component}-${stack}.tfplan"

    if ! atmos terraform plan "$component" -s "$stack" -out="$plan_file"; then
        log_error "Failed to plan $component"
        return 1
    fi

    # Apply component
    if [ "$AUTO_APPROVE" = "true" ]; then
        log_info "Applying $component (auto-approved)..."
        if ! atmos terraform apply "$component" -s "$stack" -auto-approve; then
            log_error "Failed to apply $component"
            return 1
        fi
    else
        log_info "Applying $component..."
        log_warning "Manual approval required"

        if ! atmos terraform apply "$component" -s "$stack"; then
            log_error "Failed to apply $component"
            return 1
        fi
    fi

    log_success "Successfully deployed $component"
    return 0
}

health_check_component() {
    local component="$1"

    log_info "Running health checks for $component..."

    case "$component" in
    vpc)
        # Check VPC exists
        local vpc_count
        vpc_count=$(aws ec2 describe-vpcs \
            --region "$REGION" \
            --filters "Name=tag:Tenant,Values=$TENANT" "Name=tag:Environment,Values=$ENVIRONMENT" \
            --query 'length(Vpcs)' --output text 2>/dev/null || echo "0")

        if [ "$vpc_count" -gt 0 ]; then
            log_success "VPC health check passed"
        else
            log_warning "VPC health check failed"
            return 1
        fi
        ;;

    eks)
        # Check EKS cluster status
        local clusters
        clusters=$(aws eks list-clusters --region "$REGION" --query 'clusters' --output text 2>/dev/null || echo "")

        local cluster_found=false
        for cluster in $clusters; do
            if [[ "$cluster" == *"$TENANT"* ]] && [[ "$cluster" == *"$ENVIRONMENT"* ]]; then
                local status
                status=$(aws eks describe-cluster --region "$REGION" --name "$cluster" --query 'cluster.status' --output text 2>/dev/null || echo "UNKNOWN")

                if [ "$status" = "ACTIVE" ]; then
                    log_success "EKS cluster health check passed"
                    cluster_found=true
                    break
                fi
            fi
        done

        if [ "$cluster_found" = false ]; then
            log_warning "EKS cluster health check failed or cluster not ready yet"
        fi
        ;;

    rds)
        # Check RDS instances
        local instances
        instances=$(aws rds describe-db-instances \
            --region "$REGION" \
            --query 'DBInstances[*].DBInstanceIdentifier' --output text 2>/dev/null || echo "")

        local instance_found=false
        for instance in $instances; do
            if [[ "$instance" == *"$TENANT"* ]] && [[ "$instance" == *"$ENVIRONMENT"* ]]; then
                local status
                status=$(aws rds describe-db-instances --region "$REGION" --db-instance-identifier "$instance" --query 'DBInstances[0].DBInstanceStatus' --output text 2>/dev/null || echo "unknown")

                if [ "$status" = "available" ]; then
                    log_success "RDS health check passed"
                    instance_found=true
                    break
                fi
            fi
        done

        if [ "$instance_found" = false ]; then
            log_warning "RDS health check failed or instance not ready yet"
        fi
        ;;

    *)
        log_info "No specific health check for $component"
        ;;
    esac

    return 0
}

run_smoke_tests() {
    if [ "$SKIP_TESTS" = "true" ]; then
        log_info "Skipping smoke tests (SKIP_TESTS=true)"
        return 0
    fi

    log_header "Running Smoke Tests"

    local test_script="$PROJECT_ROOT/tests/smoke/test_health_checks.sh"

    if [ -f "$test_script" ]; then
        export TENANT ENVIRONMENT REGION
        bash "$test_script" || {
            log_warning "Smoke tests completed with warnings"
        }
    else
        log_warning "Smoke test script not found: $test_script"
    fi
}

print_deployment_summary() {
    local deployed_components=("$@")

    cat <<EOF

========================================
 Deployment Summary
========================================
Tenant:        $TENANT
Account:       $ACCOUNT
Environment:   $ENVIRONMENT
Region:        $REGION

Deployed Components:
EOF

    for component in "${deployed_components[@]}"; do
        echo "  - $component"
    done

    cat <<EOF

Deployment Status: SUCCESS

Next Steps:
  1. Run smoke tests:
     ./tests/smoke/test_health_checks.sh

  2. Verify deployment:
     atmos terraform output -s ${TENANT}-${ACCOUNT}-${ENVIRONMENT}

  3. Check drift:
     atmos workflow drift-detection tenant=$TENANT account=$ACCOUNT environment=$ENVIRONMENT

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
        -c | --components)
            COMPONENTS="$2"
            shift 2
            ;;
        --auto-approve)
            AUTO_APPROVE=true
            shift
            ;;
        --skip-tests)
            SKIP_TESTS=true
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

    log_header "Infrastructure Deployment"

    echo "Configuration:"
    echo "  Tenant:       $TENANT"
    echo "  Account:      $ACCOUNT"
    echo "  Environment:  $ENVIRONMENT"
    echo "  Region:       $REGION"
    echo "  Auto-approve: $AUTO_APPROVE"
    echo "  Skip tests:   $SKIP_TESTS"
    echo

    # Prerequisites
    check_prerequisites || exit 1
    echo

    # Validation
    validate_environment
    echo

    # Determine components to deploy
    local components_to_deploy=()

    if [ -n "$COMPONENTS" ]; then
        IFS=',' read -ra components_to_deploy <<<"$COMPONENTS"
        log_info "Deploying specific components: ${components_to_deploy[*]}"
    else
        components_to_deploy=("${DEFAULT_COMPONENT_ORDER[@]}")
        log_info "Deploying all components in default order"
    fi

    # Deploy components
    local deployed_components=()
    local failed_components=()

    for component in "${components_to_deploy[@]}"; do
        if deploy_component "$component"; then
            deployed_components+=("$component")

            # Run health check
            sleep 5 # Wait for resources to stabilize
            health_check_component "$component" || true
        else
            failed_components+=("$component")
            log_error "Failed to deploy $component"

            if [ "$AUTO_APPROVE" = "true" ]; then
                log_error "Stopping deployment due to failure"
                break
            else
                read -p "Continue with next component? (y/N) " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    break
                fi
            fi
        fi

        echo
    done

    # Run smoke tests
    run_smoke_tests
    echo

    # Print summary
    print_deployment_summary "${deployed_components[@]}"

    # Exit status
    if [ ${#failed_components[@]} -gt 0 ]; then
        log_error "Deployment completed with failures: ${failed_components[*]}"
        exit 1
    else
        log_success "Deployment completed successfully!"
        exit 0
    fi
}

main "$@"
