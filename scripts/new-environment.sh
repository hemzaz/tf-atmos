#!/usr/bin/env bash
#
# new-environment.sh - Environment Bootstrap Script
#
# Creates a new Atmos stack in the repository layout:
#   stacks/orgs/<tenant>/<stage>/<region>/<environment>.yaml
#   stacks/orgs/<tenant>/<stage>/<region>/<environment>/components/*.yaml
#
# The stack name follows atmos.yaml `name_template`: <tenant>-<stage>-<environment>.
# Naming context is written to settings.context (tenant/stage/environment) and
# settings.environment.account; vars only carry `region`. The S3 backend
# (native lockfile locking) is inherited from stacks/orgs/<tenant>/_defaults.yaml.
#
# Usage:
#   ./scripts/new-environment.sh [options]
#   ./scripts/new-environment.sh --interactive
#
# Examples:
#   ./scripts/new-environment.sh --tenant fnx --stage dev --environment testenv-02 --region eu-west-2
#   ./scripts/new-environment.sh --interactive
#   ./scripts/new-environment.sh --tenant fnx --stage prod --environment prod-02 --region eu-west-2 --template microservices-platform
#

set -euo pipefail

# ==============================================================================
# Configuration
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

BOLD="\033[1m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
CYAN="\033[36m"
RESET="\033[0m"

# Default configuration
TENANT=""
STAGE=""
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

# Available templates: stacks/catalog/templates/<name>.yaml, plus minimal-stack
# (VPC and state backend only, no catalog template import)
AVAILABLE_TEMPLATES=(
    "web-application"
    "microservices-platform"
    "data-pipeline"
    "serverless-api"
    "batch-processing"
    "minimal-stack"
)

# Default VPC CIDR by environment type
default_cidr() {
    case "$1" in
        staging) echo "10.10.0.0/16" ;;
        production) echo "10.20.0.0/16" ;;
        *) echo "10.0.0.0/16" ;;
    esac
}

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
    echo -e "${RED}[ERROR]${RESET} $*" >&2
}

log_step() {
    echo -e "\n${BOLD}${CYAN}==> $*${RESET}"
}

# Derived names/paths; valid once inputs are set
stack_name() { echo "${TENANT}-${STAGE}-${ENVIRONMENT}"; }
region_dir() { echo "${REPO_ROOT}/stacks/orgs/${TENANT}/${STAGE}/${REGION}"; }
stack_file() { echo "$(region_dir)/${ENVIRONMENT}.yaml"; }
components_dir() { echo "$(region_dir)/${ENVIRONMENT}/components"; }
import_prefix() { echo "orgs/${TENANT}/${STAGE}/${REGION}/${ENVIRONMENT}/components"; }

show_help() {
    cat << EOF
${BOLD}new-environment.sh - Environment Bootstrap Script${RESET}

Creates a new Atmos stack (<tenant>-<stage>-<environment>) with its stack
manifest and component files, then optionally bootstraps the state backend.

${BOLD}USAGE:${RESET}
    $0 [options]
    $0 --interactive

${BOLD}REQUIRED OPTIONS:${RESET}
    --tenant <name>           Tenant/organization name (e.g., fnx)
    --stage <name>            Stage (e.g., dev, staging, prod)
    --environment <name>      Environment name (e.g., testenv-01, prod-01)
    --region <region>         AWS region (e.g., eu-west-2)

${BOLD}OPTIONAL:${RESET}
    --account <name>          Account name for settings.environment.account (default: stage)
    --vpc-cidr <cidr>         VPC CIDR block (default: auto-assigned based on env type)
    --template <name>         Stack template to use (default: minimal-stack)
    --env-type <type>         Environment type: development, staging, production
    --interactive, -i         Interactive mode with prompts
    --force                   Overwrite existing environment
    --skip-backend            Skip the state backend bootstrap workflow
    --no-workspace            Don't run terraform init for vpc/main
    --dry-run                 Show what would be created without making changes
    --help, -h                Show this help message

${BOLD}AVAILABLE TEMPLATES:${RESET}
    web-application           Web app with VPC, RDS, monitoring
    microservices-platform    EKS-based microservices
    data-pipeline             Lambda-based data processing
    serverless-api            Serverless REST API
    batch-processing          Batch job processing
    minimal-stack             VPC and state backend only

${BOLD}EXAMPLES:${RESET}
    # Create development environment interactively
    $0 --interactive

    # Create development environment
    $0 --tenant fnx --stage dev --environment testenv-02 --region eu-west-2

    # Create production environment with a template
    $0 --tenant fnx --stage prod --environment prod-02 \\
       --region eu-west-2 --template microservices-platform --env-type production

    # Dry run to see what would be created
    $0 --tenant fnx --stage staging --environment staging-02 \\
       --region eu-west-2 --dry-run

${BOLD}FILES CREATED:${RESET}
    stacks/orgs/<tenant>/<stage>/<region>/<environment>.yaml
    stacks/orgs/<tenant>/<stage>/<region>/<environment>/components/
    +-- globals.yaml        # Catalog imports, tags, environment settings
    +-- networking.yaml     # vpc/main
    +-- security.yaml       # backend/main (state bucket)
    stacks/orgs/<tenant>/<stage>/_defaults.yaml, mixins/{tenant,stage}/  (only if missing)

${BOLD}NOTES:${RESET}
    - stacks/orgs/<tenant>/_defaults.yaml (backend, toolchain) must already exist
    - A new stage's _defaults.yaml takes account_id from \$AWS_ACCOUNT_ID
    - VPC CIDR is auto-assigned if not specified based on environment type
    - The backend is bootstrapped with: atmos workflow backend-only -f bootstrap -s <stack>

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
        echo -ne "${BOLD}$prompt${RESET} [${default}]: " >&2
    else
        echo -ne "${BOLD}$prompt${RESET}: " >&2
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

    echo -e "\n${BOLD}$prompt${RESET}" >&2
    local i=1
    for opt in "${options[@]}"; do
        echo "  $i) $opt" >&2
        i=$((i + 1))
    done

    local selection=""
    while [[ -z "$selection" || ! "$selection" =~ ^[0-9]+$ || "$selection" -lt 1 || "$selection" -gt "${#options[@]}" ]]; do
        echo -ne "Select [1-${#options[@]}]: " >&2
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

    TENANT=$(prompt_value "Tenant/Organization name" "${TENANT:-fnx}")

    local stage_options=("dev" "staging" "prod")
    STAGE=$(prompt_selection "Select stage:" "${stage_options[@]}")
    ACCOUNT=$(prompt_value "Account (settings.environment.account)" "${ACCOUNT:-$STAGE}")

    local default_env=""
    case "$STAGE" in
        dev) default_env="testenv-02" ;;
        staging) default_env="staging-02" ;;
        prod) default_env="prod-02" ;;
    esac
    ENVIRONMENT=$(prompt_value "Environment name" "$default_env")

    local region_options=("eu-west-2" "us-east-2" "us-west-2")
    REGION=$(prompt_selection "Select AWS region:" "${region_options[@]}")

    local env_type_options=("development" "staging" "production")
    ENV_TYPE=$(prompt_selection "Select environment type:" "${env_type_options[@]}")

    TEMPLATE=$(prompt_selection "Select stack template:" "${AVAILABLE_TEMPLATES[@]}")

    VPC_CIDR=$(prompt_value "VPC CIDR block" "$(default_cidr "$ENV_TYPE")")

    echo ""
    echo -e "${BOLD}Configuration Summary:${RESET}"
    echo "  Stack:       ${TENANT}-${STAGE}-${ENVIRONMENT}"
    echo "  Account:     $ACCOUNT"
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

validate_name() {
    local label="$1" value="$2"
    if [[ -z "$value" ]]; then
        log_error "$label is required"
        return 1
    elif [[ ! "$value" =~ ^[a-z][a-z0-9-]*$ ]]; then
        log_error "$label must start with a letter and contain only lowercase letters, numbers, and hyphens"
        return 1
    fi
}

validate_inputs() {
    local errors=0

    # Stage and account default to each other
    STAGE="${STAGE:-$ACCOUNT}"
    ACCOUNT="${ACCOUNT:-$STAGE}"

    validate_name "Tenant name" "$TENANT" || errors=$((errors + 1))
    validate_name "Stage" "$STAGE" || errors=$((errors + 1))
    validate_name "Account" "$ACCOUNT" || errors=$((errors + 1))
    validate_name "Environment name" "$ENVIRONMENT" || errors=$((errors + 1))

    if [[ -z "$REGION" ]]; then
        log_error "Region is required"
        errors=$((errors + 1))
    elif [[ ! "$REGION" =~ ^[a-z]{2}-[a-z]+-[0-9]$ ]]; then
        log_error "Invalid AWS region: $REGION"
        errors=$((errors + 1))
    fi

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
        errors=$((errors + 1))
    fi

    if [[ -z "$VPC_CIDR" ]]; then
        VPC_CIDR="$(default_cidr "$ENV_TYPE")"
        log_info "Using default VPC CIDR: $VPC_CIDR"
    elif [[ ! "$VPC_CIDR" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        log_error "Invalid VPC CIDR format: $VPC_CIDR"
        errors=$((errors + 1))
    fi

    # The org defaults carry the S3 backend and the Terraform toolchain pin
    if [[ ! -f "${REPO_ROOT}/stacks/orgs/${TENANT}/_defaults.yaml" ]]; then
        log_error "Missing stacks/orgs/${TENANT}/_defaults.yaml (backend and toolchain defaults)"
        log_info "Create it first, e.g. from stacks/orgs/fnx/_defaults.yaml"
        errors=$((errors + 1))
    fi

    [[ $errors -eq 0 ]]
}

check_existing_environment() {
    local file dir
    file="$(stack_file)"
    dir="$(region_dir)/${ENVIRONMENT}"

    if [[ -e "$file" || -d "$dir" ]]; then
        if [[ "$FORCE" == "true" ]]; then
            log_warning "Environment already exists. Force flag set - will overwrite."
            if [[ "$DRY_RUN" != "true" ]]; then
                rm -f "$file"
                rm -rf "$dir"
            fi
        else
            log_error "Environment already exists: $file"
            log_info "Use --force to overwrite"
            return 1
        fi
    fi

    return 0
}

# ==============================================================================
# Environment Creation
# ==============================================================================

# write_file <path> : writes stdin to <path> (or reports it in dry-run mode)
write_file() {
    local path="$1"
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create: ${path#"$REPO_ROOT"/}"
        cat > /dev/null
        return 0
    fi
    mkdir -p "$(dirname "$path")"
    cat > "$path"
    log_success "Created: ${path#"$REPO_ROOT"/}"
}

# Tenant/stage mixins and stage defaults are shared; only create them if missing
generate_shared_files() {
    log_step "Checking Shared Mixins and Defaults"

    local tenant_mixin="${REPO_ROOT}/stacks/mixins/tenant/${TENANT}.yaml"
    local stage_mixin="${REPO_ROOT}/stacks/mixins/stage/${STAGE}.yaml"
    local stage_defaults="${REPO_ROOT}/stacks/orgs/${TENANT}/${STAGE}/_defaults.yaml"

    if [[ -f "$tenant_mixin" ]]; then
        log_info "Tenant mixin already exists: mixins/tenant/${TENANT}"
    else
        write_file "$tenant_mixin" << EOF
---
settings:
  context:
    tenant: ${TENANT}
EOF
    fi

    if [[ -f "$stage_mixin" ]]; then
        log_info "Stage mixin already exists: mixins/stage/${STAGE}"
    else
        write_file "$stage_mixin" << EOF
---
settings:
  context:
    stage: ${STAGE}
EOF
    fi

    if [[ -f "$stage_defaults" ]]; then
        log_info "Stage defaults already exist: orgs/${TENANT}/${STAGE}/_defaults"
    else
        # account_id feeds the backend component (catalog/backend/defaults)
        if [[ -z "${AWS_ACCOUNT_ID:-}" ]]; then
            log_warning "AWS_ACCOUNT_ID is not set: fill settings.environment.account_id in orgs/${TENANT}/${STAGE}/_defaults.yaml"
        fi
        write_file "$stage_defaults" << EOF
---
import:
  - orgs/${TENANT}/_defaults
  - mixins/tenant/${TENANT}
  - mixins/stage/${STAGE}

settings:
  environment:
    account: ${ACCOUNT}
    account_id: "${AWS_ACCOUNT_ID:-}"
EOF
    fi
}

generate_stack_file() {
    log_step "Generating Stack Manifest"

    local region_mixin_import=""
    if [[ -f "${REPO_ROOT}/stacks/mixins/region/${REGION}.yaml" ]]; then
        region_mixin_import="  - mixins/region/${REGION}"
    else
        region_mixin_import="  # (no stacks/mixins/region/${REGION}.yaml)"
    fi

    local env_mixin_import=""
    case "$ENV_TYPE" in
        production) env_mixin_import="  - mixins/production" ;;
        development) env_mixin_import="  - mixins/development" ;;
    esac

    write_file "$(stack_file)" << EOF
---
# =============================================================================
# Stack: $(stack_name)
# =============================================================================
# Template: ${TEMPLATE}
# Environment Type: ${ENV_TYPE}
# Created by scripts/new-environment.sh on $(date -u '+%Y-%m-%d')
# =============================================================================

import:
  - catalog/_base/defaults

  # Mixins (order matters for precedence)
  - mixins/tenant/${TENANT}
  - mixins/stage/${STAGE}
${region_mixin_import}
${env_mixin_import}

  # Org and stage defaults (backend, toolchain, account)
  - orgs/${TENANT}/${STAGE}/_defaults

  # Component configurations
  - $(import_prefix)/globals
  - $(import_prefix)/networking
  - $(import_prefix)/security

vars:
  region: ${REGION}

settings:
  environment:
    account: ${ACCOUNT}
    description: "${ENVIRONMENT} (${ENV_TYPE})"
    namespace: ${ENVIRONMENT}
    vpc_cidr: "${VPC_CIDR}"
  context:
    tenant: ${TENANT}
    stage: ${STAGE}
    environment: ${ENVIRONMENT}
EOF
}

generate_component_files() {
    log_step "Generating Component Configurations"

    # Subnets follow the vpc/defaults layout (x.y.1-3.0/24 private,
    # x.y.101-103.0/24 public) inside the VPC's /16
    local net="${VPC_CIDR%.*.*/*}"
    local subnets_block
    if [[ "$VPC_CIDR" == */16 ]]; then
        subnets_block="        private_subnets:
          - \"${net}.1.0/24\"
          - \"${net}.2.0/24\"
          - \"${net}.3.0/24\"
        public_subnets:
          - \"${net}.101.0/24\"
          - \"${net}.102.0/24\"
          - \"${net}.103.0/24\""
    else
        log_warning "VPC CIDR is not a /16: set private_subnets/public_subnets for vpc/main by hand"
        subnets_block="        # Set private_subnets/public_subnets inside ${VPC_CIDR} (vpc/defaults assumes 10.0.0.0/16)"
    fi

    local template_import=""
    if [[ "$TEMPLATE" != "minimal-stack" ]]; then
        template_import="  - catalog/templates/${TEMPLATE}"
    fi

    # Environment sizing, exposed to component templates as {{ .settings.environment.* }}
    local is_prod="false"
    [[ "$ENV_TYPE" == "production" ]] && is_prod="true"
    local instance_type="t3.medium" db_instance_class="db.t3.micro"
    local log_retention=30 backup_retention=7
    case "$ENV_TYPE" in
        production) instance_type="m5.large"; db_instance_class="db.r5.large"; log_retention=90; backup_retention=30 ;;
        staging) instance_type="t3.large"; db_instance_class="db.t3.medium" ;;
    esac

    write_file "$(components_dir)/globals.yaml" << EOF
---
# Environment-wide settings for $(stack_name)

import:
  - catalog/vpc/defaults
  - catalog/backend/defaults
${template_import}

vars:
  tags:
    Template: "${TEMPLATE}"

settings:
  environment:
    env_type: ${ENV_TYPE}
    instance_type_default: "${instance_type}"
    rds_instance_class_default: "${db_instance_class}"
    log_retention_days: ${log_retention}
    backup_retention_days: ${backup_retention}
    enable_deletion_protection: ${is_prod}
    enable_multi_az: ${is_prod}
    enable_vpc_flow_logs: ${is_prod}
EOF

    write_file "$(components_dir)/networking.yaml" << EOF
---
# Networking for $(stack_name)

import:
  - $(import_prefix)/globals

components:
  terraform:
    vpc/main:
      metadata:
        component: vpc
        inherits:
          - vpc/defaults
      vars:
        vpc_cidr: "${VPC_CIDR}"
${subnets_block}
        enable_flow_logs: "{{ .settings.environment.enable_vpc_flow_logs }}"
EOF

    write_file "$(components_dir)/security.yaml" << EOF
---
# State backend for $(stack_name)
# Bootstrap with: atmos workflow backend-only -f bootstrap -s $(stack_name)

import:
  - $(import_prefix)/globals

components:
  terraform:
    backend/main:
      metadata:
        component: backend
        inherits:
          - backend
EOF
}

validate_generated_stack() {
    [[ "$DRY_RUN" == "true" ]] && return 0

    log_step "Validating Generated Stack"

    if atmos --chdir "$REPO_ROOT" describe stacks -s "$(stack_name)" --process-functions=false >/dev/null; then
        log_success "Stack resolves: $(stack_name)"
    else
        log_error "atmos could not resolve stack $(stack_name); review the generated files"
        return 1
    fi
}

initialize_backend() {
    if [[ "$SKIP_BACKEND" == "true" ]]; then
        log_info "Skipping backend bootstrap (--skip-backend)"
        return 0
    fi

    log_step "Bootstrapping State Backend"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would run: atmos workflow backend-only -f bootstrap -s $(stack_name)"
        return 0
    fi

    # Creates the S3 bucket (native lockfile locking) and brings it under the
    # backend/main component; the workflow asks for confirmation before applying.
    atmos --chdir "$REPO_ROOT" workflow backend-only -f bootstrap -s "$(stack_name)"
}

initialize_workspace() {
    if [[ "$INITIALIZE_WORKSPACE" != "true" ]]; then
        log_info "Skipping workspace initialization (--no-workspace)"
        return 0
    fi

    log_step "Initializing Terraform Workspace"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would run: atmos terraform init vpc/main -s $(stack_name)"
        return 0
    fi

    if atmos --chdir "$REPO_ROOT" terraform init vpc/main -s "$(stack_name)"; then
        log_success "Terraform initialized for stack: $(stack_name)"
    else
        log_warning "Could not initialize Terraform automatically"
        log_info "Run manually: atmos terraform init vpc/main -s $(stack_name)"
    fi
}

# ==============================================================================
# Summary and Next Steps
# ==============================================================================

show_summary() {
    log_step "Environment Created Successfully"

    echo ""
    echo -e "${BOLD}Stack Details:${RESET}"
    echo "  Stack Name:     $(stack_name)"
    echo "  Manifest:       $(stack_file)"
    echo "  Template:       $TEMPLATE"
    echo "  Environment:    $ENV_TYPE"
    echo "  Region:         $REGION"
    echo "  VPC CIDR:       $VPC_CIDR"
    echo ""

    echo -e "${BOLD}Next Steps:${RESET}"
    echo ""
    echo -e "  1. Review and customize the configuration:"
    echo -e "     ${CYAN}atmos describe stacks -s $(stack_name)${RESET}"
    echo ""
    echo -e "  2. Validate the stack:"
    echo -e "     ${CYAN}atmos workflow validate -f validate -s $(stack_name)${RESET}"
    echo ""
    echo -e "  3. Plan the deployment:"
    echo -e "     ${CYAN}atmos workflow plan -f plan-environment -s $(stack_name)${RESET}"
    echo ""
    echo -e "  4. Deploy the environment:"
    echo -e "     ${CYAN}atmos workflow full -f bootstrap -s $(stack_name)${RESET}"
    echo -e "     ${CYAN}atmos workflow deploy -f deploy-full-stack -s $(stack_name)${RESET}"
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
            --stage)
                STAGE="$2"
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
    if [[ "$INTERACTIVE" == "true" ]] || [[ -z "$TENANT" && -z "$STAGE" && -z "$ACCOUNT" && -z "$ENVIRONMENT" && -z "$REGION" ]]; then
        run_interactive
    fi

    if ! validate_inputs; then
        exit 1
    fi

    if ! check_existing_environment; then
        exit 1
    fi

    generate_shared_files
    generate_stack_file
    generate_component_files
    validate_generated_stack
    initialize_backend
    initialize_workspace

    show_summary

    exit 0
}

main "$@"
