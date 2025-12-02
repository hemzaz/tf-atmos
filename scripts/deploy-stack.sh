#!/usr/bin/env bash
#
# deploy-stack.sh - Smart Deployment Script for Atmos Stack Templates
#
# This script provides intelligent deployment automation for the Alexandria Library
# stack templates, handling dependency ordering, validation, and rollback capabilities.
#
# Usage:
#   ./scripts/deploy-stack.sh --template <template-name> --stack <stack-name> [options]
#
# Examples:
#   ./scripts/deploy-stack.sh --template web-application --stack mycompany-dev-testenv-01
#   ./scripts/deploy-stack.sh --template microservices-platform --stack mycompany-prod-prod-01 --auto-approve
#   ./scripts/deploy-stack.sh --template serverless-api --stack mycompany-staging-stage-01 --dry-run
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
    RESET="\033[0m"
fi

# Default configuration
TEMPLATE_NAME=""
STACK_NAME=""
DRY_RUN="false"
AUTO_APPROVE="false"
PARALLEL="false"
SKIP_VALIDATION="false"
ENABLE_ROLLBACK="true"
VERBOSE="false"
REPORT_DIR="${REPO_ROOT}/reports"
PLAN_DIR="${REPO_ROOT}/plans"
LOG_FILE=""

# Template to component mapping (deployment order)
declare -A TEMPLATE_COMPONENTS
TEMPLATE_COMPONENTS["web-application"]="vpc securitygroup iam rds monitoring"
TEMPLATE_COMPONENTS["microservices-platform"]="vpc securitygroup iam eks eks-addons monitoring secretsmanager"
TEMPLATE_COMPONENTS["data-pipeline"]="vpc securitygroup iam lambda apigateway monitoring"
TEMPLATE_COMPONENTS["serverless-api"]="vpc securitygroup iam lambda apigateway monitoring"
TEMPLATE_COMPONENTS["batch-processing"]="vpc securitygroup iam lambda monitoring"
TEMPLATE_COMPONENTS["full-stack"]="vpc securitygroup iam eks eks-addons rds monitoring secretsmanager"
TEMPLATE_COMPONENTS["minimal-stack"]="vpc securitygroup"

# Estimated deployment times (minutes)
declare -A COMPONENT_TIMES
COMPONENT_TIMES["vpc"]=5
COMPONENT_TIMES["securitygroup"]=2
COMPONENT_TIMES["iam"]=3
COMPONENT_TIMES["eks"]=15
COMPONENT_TIMES["eks-addons"]=8
COMPONENT_TIMES["rds"]=10
COMPONENT_TIMES["monitoring"]=3
COMPONENT_TIMES["secretsmanager"]=2
COMPONENT_TIMES["lambda"]=3
COMPONENT_TIMES["apigateway"]=4
COMPONENT_TIMES["acm"]=2
COMPONENT_TIMES["dns"]=2
COMPONENT_TIMES["ec2"]=5
COMPONENT_TIMES["ecs"]=8
COMPONENT_TIMES["backup"]=3
COMPONENT_TIMES["cost-optimization"]=2
COMPONENT_TIMES["security-monitoring"]=3
COMPONENT_TIMES["external-secrets"]=3

# Track deployment state for rollback
DEPLOYED_COMPONENTS=()
DEPLOYMENT_START_TIME=""
DEPLOYMENT_END_TIME=""

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

log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${CYAN}[VERBOSE]${RESET} $*"
    fi
}

show_help() {
    cat << EOF
${BOLD}deploy-stack.sh - Smart Deployment Script for Atmos Stack Templates${RESET}

${BOLD}USAGE:${RESET}
    $0 --template <template-name> --stack <stack-name> [options]

${BOLD}REQUIRED ARGUMENTS:${RESET}
    --template, -t <name>     Template name from Alexandria Library
                              Options: web-application, microservices-platform,
                                       data-pipeline, serverless-api, batch-processing,
                                       full-stack, minimal-stack
    --stack, -s <name>        Target stack name (e.g., mycompany-dev-testenv-01)

${BOLD}OPTIONS:${RESET}
    --dry-run                 Show what would be deployed without making changes
    --auto-approve            Skip confirmation prompts (use with caution)
    --parallel                Enable parallel deployment where possible
    --skip-validation         Skip pre-deployment validation checks
    --no-rollback             Disable automatic rollback on failure
    --verbose, -v             Enable verbose output
    --report-dir <path>       Directory for deployment reports (default: ./reports)
    --help, -h                Show this help message

${BOLD}EXAMPLES:${RESET}
    # Deploy web application template to development
    $0 --template web-application --stack mycompany-dev-testenv-01

    # Deploy with auto-approve for CI/CD
    $0 --template microservices-platform --stack mycompany-prod-prod-01 --auto-approve

    # Dry run to see deployment plan
    $0 --template serverless-api --stack mycompany-staging-stage-01 --dry-run

    # Deploy with verbose output
    $0 --template full-stack --stack mycompany-dev-dev-01 --verbose

${BOLD}AVAILABLE TEMPLATES:${RESET}
    web-application         Web application with VPC, RDS, and monitoring
    microservices-platform  Kubernetes-based microservices with EKS
    data-pipeline           Data processing with Lambda and API Gateway
    serverless-api          Serverless REST API
    batch-processing        Batch job processing infrastructure
    full-stack              Complete production infrastructure
    minimal-stack           Basic VPC and security groups only

${BOLD}NOTES:${RESET}
    - Components are deployed in dependency order
    - Progress and estimated time remaining shown during deployment
    - Rollback automatically triggered on failures (unless --no-rollback)
    - Deployment report generated in reports/ directory

EOF
}

# ==============================================================================
# Prerequisite Checks
# ==============================================================================

check_prerequisites() {
    log_step "Checking Prerequisites"

    local errors=0

    # Check AWS CLI
    log_info "Checking AWS CLI..."
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found. Please install: https://aws.amazon.com/cli/"
        ((errors++))
    else
        local aws_version=$(aws --version 2>&1 | head -1)
        log_success "AWS CLI found: $aws_version"
    fi

    # Check AWS credentials
    log_info "Checking AWS credentials..."
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or expired"
        log_info "Run: aws configure or set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY"
        ((errors++))
    else
        local account_id=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
        local identity=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null)
        log_success "AWS credentials valid - Account: $account_id"
        log_verbose "Identity: $identity"
    fi

    # Check Terraform
    log_info "Checking Terraform..."
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform not found. Please install: https://terraform.io/downloads"
        ((errors++))
    else
        local tf_version=$(terraform version -json 2>/dev/null | jq -r '.terraform_version' 2>/dev/null || terraform version | head -1)
        log_success "Terraform found: $tf_version"
    fi

    # Check Atmos
    log_info "Checking Atmos CLI..."
    if ! command -v atmos &> /dev/null; then
        log_error "Atmos CLI not found. Please install: brew install cloudposse/tap/atmos"
        ((errors++))
    else
        local atmos_version=$(atmos version 2>/dev/null | head -1 || echo "unknown")
        log_success "Atmos CLI found: $atmos_version"
    fi

    # Check jq (optional but recommended)
    if command -v jq &> /dev/null; then
        log_success "jq found (for JSON processing)"
    else
        log_warning "jq not found (recommended for better output formatting)"
    fi

    if [[ $errors -gt 0 ]]; then
        log_error "Prerequisites check failed with $errors error(s)"
        return 1
    fi

    log_success "All prerequisites satisfied"
    return 0
}

# ==============================================================================
# Validation Functions
# ==============================================================================

validate_template() {
    local template="$1"

    if [[ -z "${TEMPLATE_COMPONENTS[$template]:-}" ]]; then
        log_error "Unknown template: $template"
        log_info "Available templates: ${!TEMPLATE_COMPONENTS[*]}"
        return 1
    fi

    log_success "Template validated: $template"
    return 0
}

validate_stack() {
    local stack="$1"

    log_info "Validating stack: $stack"

    # Check if stack exists in Atmos configuration
    if ! atmos describe stacks 2>/dev/null | grep -q "$stack"; then
        log_warning "Stack $stack may not exist in Atmos configuration"
        log_info "Available stacks:"
        atmos describe stacks 2>/dev/null | head -20 || true

        if [[ "$AUTO_APPROVE" != "true" ]]; then
            echo -n "Continue anyway? (y/n): "
            read -r response
            if [[ "$response" != "y" ]]; then
                return 1
            fi
        fi
    else
        log_success "Stack found in Atmos configuration"
    fi

    return 0
}

run_pre_deployment_validation() {
    log_step "Running Pre-Deployment Validation"

    local components="${TEMPLATE_COMPONENTS[$TEMPLATE_NAME]}"
    local validation_errors=0

    for component in $components; do
        log_info "Validating component: $component"

        # Check if component directory exists
        if [[ ! -d "${REPO_ROOT}/components/terraform/$component" ]]; then
            log_warning "Component directory not found: $component"
            continue
        fi

        # Run terraform validate
        if [[ "$DRY_RUN" != "true" ]]; then
            if atmos terraform validate "$component" -s "$STACK_NAME" 2>/dev/null; then
                log_success "Component $component validated"
            else
                log_warning "Component $component validation had issues"
                ((validation_errors++))
            fi
        else
            log_info "[DRY-RUN] Would validate component: $component"
        fi
    done

    if [[ $validation_errors -gt 0 ]]; then
        log_warning "Pre-deployment validation completed with $validation_errors warning(s)"
    else
        log_success "Pre-deployment validation completed successfully"
    fi

    return 0
}

# ==============================================================================
# Deployment Functions
# ==============================================================================

calculate_total_time() {
    local components="${TEMPLATE_COMPONENTS[$TEMPLATE_NAME]}"
    local total=0

    for component in $components; do
        local time="${COMPONENT_TIMES[$component]:-5}"
        ((total += time))
    done

    echo $total
}

show_deployment_plan() {
    log_step "Deployment Plan"

    local components="${TEMPLATE_COMPONENTS[$TEMPLATE_NAME]}"
    local total_time=$(calculate_total_time)
    local step=1

    echo ""
    echo -e "${BOLD}Template:${RESET} $TEMPLATE_NAME"
    echo -e "${BOLD}Stack:${RESET} $STACK_NAME"
    echo -e "${BOLD}Estimated Time:${RESET} ~${total_time} minutes"
    echo ""
    echo -e "${BOLD}Components to deploy (in order):${RESET}"
    echo ""

    for component in $components; do
        local time="${COMPONENT_TIMES[$component]:-5}"
        printf "  %2d. %-25s (~%d min)\n" $step "$component" $time
        ((step++))
    done

    echo ""
}

deploy_component() {
    local component="$1"
    local component_num="$2"
    local total_components="$3"

    local start_time=$(date +%s)
    local estimated_time="${COMPONENT_TIMES[$component]:-5}"

    echo ""
    log_step "[$component_num/$total_components] Deploying: $component (est. ~${estimated_time} min)"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would deploy component: $component"
        log_info "[DRY-RUN] Command: atmos terraform apply $component -s $STACK_NAME -auto-approve"
        return 0
    fi

    # Create plan first
    log_info "Creating execution plan..."
    local plan_file="${PLAN_DIR}/${STACK_NAME}/${component}.tfplan"
    mkdir -p "$(dirname "$plan_file")"

    if ! atmos terraform plan "$component" -s "$STACK_NAME" 2>&1 | tee -a "${LOG_FILE:-/dev/null}"; then
        log_error "Plan failed for component: $component"
        return 1
    fi

    # Apply the plan
    log_info "Applying changes..."
    if [[ "$AUTO_APPROVE" == "true" ]]; then
        if ! atmos terraform apply "$component" -s "$STACK_NAME" -auto-approve 2>&1 | tee -a "${LOG_FILE:-/dev/null}"; then
            log_error "Apply failed for component: $component"
            return 1
        fi
    else
        if ! atmos terraform apply "$component" -s "$STACK_NAME" 2>&1 | tee -a "${LOG_FILE:-/dev/null}"; then
            log_error "Apply failed for component: $component"
            return 1
        fi
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    log_success "Component $component deployed successfully (${duration}s)"
    DEPLOYED_COMPONENTS+=("$component")

    return 0
}

show_progress() {
    local current="$1"
    local total="$2"
    local elapsed="$3"
    local estimated_total="$4"

    local percent=$((current * 100 / total))
    local remaining=$((estimated_total - elapsed / 60))

    if [[ $remaining -lt 0 ]]; then
        remaining=0
    fi

    echo ""
    echo -e "${BOLD}Progress:${RESET} $current/$total components ($percent%)"
    echo -e "${BOLD}Elapsed:${RESET} $((elapsed / 60)) min $((elapsed % 60)) sec"
    echo -e "${BOLD}Estimated Remaining:${RESET} ~$remaining min"
    echo ""
}

run_deployment() {
    log_step "Starting Deployment"

    DEPLOYMENT_START_TIME=$(date +%s)

    local components="${TEMPLATE_COMPONENTS[$TEMPLATE_NAME]}"
    local total_components=$(echo "$components" | wc -w | tr -d ' ')
    local total_estimated_time=$(calculate_total_time)
    local current=0

    mkdir -p "$PLAN_DIR"
    mkdir -p "$REPORT_DIR"

    # Initialize log file
    LOG_FILE="${REPORT_DIR}/deploy-${STACK_NAME}-$(date +%Y%m%d-%H%M%S).log"
    touch "$LOG_FILE"

    log_info "Deployment log: $LOG_FILE"

    for component in $components; do
        ((current++))

        local elapsed=$(($(date +%s) - DEPLOYMENT_START_TIME))
        show_progress $current $total_components $elapsed $((total_estimated_time * 60))

        if ! deploy_component "$component" "$current" "$total_components"; then
            log_error "Deployment failed at component: $component"

            if [[ "$ENABLE_ROLLBACK" == "true" && "${#DEPLOYED_COMPONENTS[@]}" -gt 0 ]]; then
                log_warning "Initiating rollback..."
                perform_rollback
            fi

            return 1
        fi
    done

    DEPLOYMENT_END_TIME=$(date +%s)

    log_success "All components deployed successfully"
    return 0
}

# ==============================================================================
# Rollback Functions
# ==============================================================================

perform_rollback() {
    log_step "Performing Rollback"

    if [[ "${#DEPLOYED_COMPONENTS[@]}" -eq 0 ]]; then
        log_info "No components to rollback"
        return 0
    fi

    log_warning "Rolling back ${#DEPLOYED_COMPONENTS[@]} deployed component(s)..."

    # Rollback in reverse order
    local i
    for ((i=${#DEPLOYED_COMPONENTS[@]}-1; i>=0; i--)); do
        local component="${DEPLOYED_COMPONENTS[$i]}"
        log_info "Rolling back: $component"

        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY-RUN] Would destroy component: $component"
        else
            if atmos terraform destroy "$component" -s "$STACK_NAME" -auto-approve 2>&1 | tee -a "${LOG_FILE:-/dev/null}"; then
                log_success "Rolled back: $component"
            else
                log_error "Failed to rollback: $component"
                log_warning "Manual cleanup may be required"
            fi
        fi
    done

    log_warning "Rollback completed. Check resources for any orphaned infrastructure."
}

# ==============================================================================
# Reporting Functions
# ==============================================================================

generate_report() {
    log_step "Generating Deployment Report"

    local report_file="${REPORT_DIR}/deployment-report-${STACK_NAME}-$(date +%Y%m%d-%H%M%S).md"
    mkdir -p "$REPORT_DIR"

    local total_time=0
    if [[ -n "$DEPLOYMENT_START_TIME" && -n "$DEPLOYMENT_END_TIME" ]]; then
        total_time=$((DEPLOYMENT_END_TIME - DEPLOYMENT_START_TIME))
    fi

    cat > "$report_file" << EOF
# Deployment Report

## Summary

| Field | Value |
|-------|-------|
| **Template** | $TEMPLATE_NAME |
| **Stack** | $STACK_NAME |
| **Date** | $(date -u '+%Y-%m-%d %H:%M:%S UTC') |
| **Duration** | $((total_time / 60)) min $((total_time % 60)) sec |
| **Status** | ${1:-UNKNOWN} |
| **Dry Run** | $DRY_RUN |
| **Auto Approve** | $AUTO_APPROVE |

## Deployed Components

| # | Component | Status |
|---|-----------|--------|
EOF

    local i=1
    for component in ${TEMPLATE_COMPONENTS[$TEMPLATE_NAME]}; do
        local status="PENDING"
        for deployed in "${DEPLOYED_COMPONENTS[@]}"; do
            if [[ "$deployed" == "$component" ]]; then
                status="DEPLOYED"
                break
            fi
        done
        echo "| $i | $component | $status |" >> "$report_file"
        ((i++))
    done

    cat >> "$report_file" << EOF

## Environment Details

- **AWS Account**: $(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "N/A")
- **AWS Region**: ${AWS_REGION:-$(aws configure get region 2>/dev/null || echo "N/A")}
- **Terraform Version**: $(terraform version -json 2>/dev/null | jq -r '.terraform_version' 2>/dev/null || echo "N/A")
- **Atmos Version**: $(atmos version 2>/dev/null | head -1 || echo "N/A")

## Log File

\`${LOG_FILE:-N/A}\`

## Next Steps

EOF

    if [[ "$1" == "SUCCESS" ]]; then
        cat >> "$report_file" << EOF
1. Verify deployed resources in AWS Console
2. Run post-deployment tests
3. Update documentation as needed
4. Configure monitoring alerts

## Verification Commands

\`\`\`bash
# View stack outputs
atmos terraform output vpc -s $STACK_NAME

# List all resources
atmos describe stacks | grep $STACK_NAME
\`\`\`
EOF
    else
        cat >> "$report_file" << EOF
1. Review the error logs
2. Check AWS Console for any partially created resources
3. Run manual cleanup if rollback was incomplete
4. Fix the issue and retry deployment

## Troubleshooting

\`\`\`bash
# Check component state
atmos terraform state list vpc -s $STACK_NAME

# Re-run failed component
atmos terraform apply <component> -s $STACK_NAME
\`\`\`
EOF
    fi

    cat >> "$report_file" << EOF

---
*Report generated by deploy-stack.sh*
EOF

    log_success "Report generated: $report_file"
    echo "$report_file"
}

# ==============================================================================
# Main Execution
# ==============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --template|-t)
                TEMPLATE_NAME="$2"
                shift 2
                ;;
            --stack|-s)
                STACK_NAME="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --auto-approve)
                AUTO_APPROVE="true"
                shift
                ;;
            --parallel)
                PARALLEL="true"
                shift
                ;;
            --skip-validation)
                SKIP_VALIDATION="true"
                shift
                ;;
            --no-rollback)
                ENABLE_ROLLBACK="false"
                shift
                ;;
            --verbose|-v)
                VERBOSE="true"
                shift
                ;;
            --report-dir)
                REPORT_DIR="$2"
                shift 2
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

validate_args() {
    if [[ -z "$TEMPLATE_NAME" ]]; then
        log_error "Template name is required"
        show_help
        exit 1
    fi

    if [[ -z "$STACK_NAME" ]]; then
        log_error "Stack name is required"
        show_help
        exit 1
    fi
}

main() {
    parse_args "$@"
    validate_args

    echo ""
    echo -e "${BOLD}${CYAN}======================================${RESET}"
    echo -e "${BOLD}${CYAN}  Atmos Stack Deployment Automation  ${RESET}"
    echo -e "${BOLD}${CYAN}======================================${RESET}"
    echo ""

    # Run prerequisite checks
    if ! check_prerequisites; then
        exit 1
    fi

    # Validate template
    if ! validate_template "$TEMPLATE_NAME"; then
        exit 1
    fi

    # Validate stack
    if ! validate_stack "$STACK_NAME"; then
        exit 1
    fi

    # Show deployment plan
    show_deployment_plan

    # Pre-deployment validation
    if [[ "$SKIP_VALIDATION" != "true" ]]; then
        if ! run_pre_deployment_validation; then
            log_error "Pre-deployment validation failed"
            exit 1
        fi
    fi

    # Confirmation
    if [[ "$DRY_RUN" != "true" && "$AUTO_APPROVE" != "true" ]]; then
        echo ""
        echo -e "${YELLOW}Ready to deploy. This will create/modify AWS resources.${RESET}"
        echo -n "Continue? (y/n): "
        read -r response
        if [[ "$response" != "y" ]]; then
            log_info "Deployment cancelled"
            exit 0
        fi
    fi

    # Run deployment
    if run_deployment; then
        generate_report "SUCCESS"
        echo ""
        log_success "Deployment completed successfully!"
        echo ""
        exit 0
    else
        generate_report "FAILED"
        echo ""
        log_error "Deployment failed. See report for details."
        echo ""
        exit 1
    fi
}

# Run main function
main "$@"
