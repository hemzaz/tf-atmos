#!/usr/bin/env bash
# =============================================================================
# Atmos Infrastructure Quickstart Script
# =============================================================================
# One-command deployment for complete infrastructure environment
#
# Usage:
#   ./scripts/quickstart.sh --tenant fnx --stage dev --environment testenv-01
#   ./scripts/quickstart.sh --tenant fnx --stage prod --environment production --region eu-west-2
#   ./scripts/quickstart.sh --help
#
# This script will:
#   1. Check all prerequisites (AWS CLI, Terraform, Atmos)
#   2. Validate AWS credentials and permissions
#   3. Bootstrap the S3 state backend (native lockfile locking)
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
# Tool versions are pinned in .atmos.env (Terraform itself is installed by the
# Atmos toolchain from stacks/orgs/<tenant>/_defaults.yaml dependencies.tools)
# shellcheck source=../.atmos.env
source "$PROJECT_ROOT/.atmos.env"
DEFAULT_TERRAFORM_VERSION="$TERRAFORM_VERSION"
DEFAULT_ATMOS_VERSION="$ATMOS_VERSION"

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
    $SCRIPT_NAME --tenant <name> --stage <name> --environment <name> [OPTIONS]

${WHITE}Required Parameters:${NC}
    --tenant, -t        Tenant name (e.g., 'fnx')
    --stage, -s         Stage (e.g., 'dev', 'staging', 'prod'); --account/-a is an alias
    --environment, -e   Environment name (e.g., 'testenv-01', 'production')

    The Atmos stack is <tenant>-<stage>-<environment> (e.g. fnx-dev-testenv-01).

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
    $SCRIPT_NAME --tenant fnx --stage dev --environment testenv-01

    # Deploy production environment with specific profile
    $SCRIPT_NAME --tenant fnx --stage prod --environment production --profile prod-admin

    # Plan only (no changes)
    $SCRIPT_NAME --tenant fnx --stage dev --environment testenv-01 --plan-only

    # Dry run to see what would happen
    $SCRIPT_NAME --tenant fnx --stage dev --environment testenv-01 --dry-run

${WHITE}Environment Variables:${NC}
    AWS_ACCOUNT_ID              Override AWS account ID
    AWS_PROFILE                 AWS CLI profile (overridden by --profile)
    AWS_REGION                  AWS region (overridden by --region)

${WHITE}For more information:${NC}
    See docs/DEPLOYMENT.md
EOF
}

# Parse command line arguments
parse_args() {
    TENANT=""
    STAGE=""
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
            --stage|-s|--account|-a)
                STAGE="$2"
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
    [[ -z "$STAGE" ]] && missing_params+=("--stage")
    [[ -z "$ENVIRONMENT" ]] && missing_params+=("--environment")

    if [[ ${#missing_params[@]} -gt 0 ]]; then
        log_error "Missing required parameters: ${missing_params[*]}"
        echo
        print_usage
        exit 1
    fi

    # Construct stack name (atmos.yaml name_template)
    STACK_NAME="${TENANT}-${STAGE}-${ENVIRONMENT}"
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
        errors=$((errors + 1))
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
            warnings=$((warnings + 1))
        fi
    else
        echo -e "${YELLOW}NOT ON PATH${NC}"
        log_info "Atmos installs Terraform ${DEFAULT_TERRAFORM_VERSION} from the stack toolchain (dependencies.tools) on first use"
    fi

    # Check Atmos
    echo -n "Checking Atmos... "
    if command_exists atmos; then
        local atmos_version
        atmos_version=$(atmos version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
        if version_ge "$atmos_version" "$DEFAULT_ATMOS_VERSION"; then
            echo -e "${GREEN}OK${NC} (version: $atmos_version)"
        else
            echo -e "${RED}TOO OLD${NC} (version: $atmos_version, required: >= $DEFAULT_ATMOS_VERSION)"
            errors=$((errors + 1))
        fi
    else
        echo -e "${RED}NOT FOUND${NC}"
        log_error "Atmos is required. Install from: https://atmos.tools/install"
        errors=$((errors + 1))
    fi

    # Check jq
    echo -n "Checking jq... "
    if command_exists jq; then
        local jq_version
        jq_version=$(jq --version 2>/dev/null | tr -d 'jq-' || echo "unknown")
        echo -e "${GREEN}OK${NC} (version: $jq_version)"
    else
        echo -e "${YELLOW}WARNING${NC} - jq is recommended for JSON processing"
        warnings=$((warnings + 1))
    fi

    # Check Git
    echo -n "Checking Git... "
    if command_exists git; then
        local git_version
        git_version=$(git --version | cut -d' ' -f3)
        echo -e "${GREEN}OK${NC} (version: $git_version)"
    else
        echo -e "${YELLOW}WARNING${NC} - Git is recommended"
        warnings=$((warnings + 1))
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

    cd "$PROJECT_ROOT"

    echo -n "Looking for stack '$STACK_NAME' in Atmos... "
    if atmos list stacks 2>/dev/null | grep -qx "$STACK_NAME"; then
        echo -e "${GREEN}OK${NC}"
        return 0
    fi
    echo -e "${YELLOW}NOT FOUND${NC}"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] Would offer to create it with scripts/new-environment.sh"
        return 0
    fi

    echo "Would you like to create it with scripts/new-environment.sh? [y/N]"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        create_stack_from_template
    else
        log_error "Stack configuration is required. Create it with scripts/new-environment.sh."
        exit 1
    fi
}

# Create the stack with the shared generator (current layout, settings.context naming)
create_stack_from_template() {
    log_info "Creating stack configuration..."

    "$SCRIPT_DIR/new-environment.sh" \
        --tenant "$TENANT" \
        --stage "$STAGE" \
        --environment "$ENVIRONMENT" \
        --region "$REGION" \
        --skip-backend \
        --no-workspace
}

# Setup backend infrastructure
setup_backend() {
    log_step "Setting Up Backend Infrastructure"

    if [[ "$SKIP_BACKEND" == "true" ]]; then
        log_info "Skipping backend setup (--skip-backend flag set)"
        return 0
    fi

    cd "$PROJECT_ROOT"

    # S3 state bucket with native lockfile locking (no DynamoDB), managed by backend/main
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] Would run: atmos workflow backend-only -f bootstrap -s $STACK_NAME"
        return 0
    fi

    atmos workflow backend-only -f bootstrap -s "$STACK_NAME"

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
        atmos workflow plan -f plan-environment -s "$STACK_NAME"

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

    # apply-environment asks for confirmation per plan; with --auto-approve the
    # whole stack is deployed non-interactively (the CI path of that workflow)
    local apply_cmd=(atmos workflow apply -f apply-environment -s "$STACK_NAME")
    if [[ "$AUTO_APPROVE" == "true" ]]; then
        apply_cmd=(atmos terraform deploy -s "$STACK_NAME")
    fi

    if "${apply_cmd[@]}"; then
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
    echo "  Stage:       $STAGE"
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
    echo "  S3 Bucket:      ${TENANT}-terraform-state (native lockfile locking)"
    echo

    echo -e "${WHITE}Useful Commands:${NC}"
    echo "  # View stack outputs"
    echo "  atmos terraform output vpc/main -s $STACK_NAME"
    echo
    echo "  # Plan changes"
    echo "  atmos workflow plan -f plan-environment -s $STACK_NAME"
    echo
    echo "  # Apply changes"
    echo "  atmos workflow apply -f apply-environment -s $STACK_NAME"
    echo
    echo "  # Destroy environment"
    echo "  atmos workflow destroy -f destroy-environment   # prompts for the stack name"
    echo

    echo -e "${WHITE}Documentation:${NC}"
    echo "  - Deployment Guide:  docs/DEPLOYMENT.md"
    echo "  - Operations Guide:  docs/OPERATIONS.md"
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
