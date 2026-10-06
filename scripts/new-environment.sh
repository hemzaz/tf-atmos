#!/usr/bin/env bash
#
# new-environment.sh - Environment Bootstrap Script
#
# Creates a new Atmos stack in the repository layout:
#   stacks/orgs/<tenant>/<stage>/<region>.yaml
#   stacks/orgs/<tenant>/<stage>/<region>/components/*.yaml
# or, for a lane (--name), stacks/orgs/<tenant>/<stage>/<region>/<name>.yaml and
# stacks/orgs/<tenant>/<stage>/<region>/<name>/components/*.yaml.
#
# The stack name follows atmos.yaml `name_template`:
# <tenant>-<environment>-<stage>[-<name>], environment being the region's Cloud
# Posse code (ue1), set by the region mixin (scripts/stack-name.sh). The stack
# writes settings.context tenant/stage (and name for a lane) and
# settings.environment.account; vars only carry `region`. The S3 backend
# (native lockfile locking) is inherited from stacks/orgs/<tenant>/_defaults.yaml.
#
# Usage:
#   ./scripts/new-environment.sh [options]
#   ./scripts/new-environment.sh --interactive
#
# Examples:
#   ./scripts/new-environment.sh --tenant fnx --stage dev --region us-west-2
#   ./scripts/new-environment.sh --interactive
#   ./scripts/new-environment.sh --tenant fnx --stage dev --name perf --region us-east-1 --template microservices-platform
#

set -euo pipefail

# ==============================================================================
# Configuration
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
# shellcheck source=stack-name.sh
source "${SCRIPT_DIR}/stack-name.sh"

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
NAME=""
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

# Derived names/paths; valid once inputs are set. A lane (NAME) lives under its
# region directory, next to the stage's own <region>/components.
this_stack() { stack_name "$TENANT" "$REGION" "$STAGE" "$NAME"; }
region_dir() { echo "${REPO_ROOT}/stacks/orgs/${TENANT}/${STAGE}/${REGION}"; }
stack_file() { if [[ -n "$NAME" ]]; then echo "$(region_dir)/${NAME}.yaml"; else echo "$(region_dir).yaml"; fi; }
components_dir() { echo "$(region_dir)${NAME:+/$NAME}/components"; }
import_prefix() { echo "orgs/${TENANT}/${STAGE}/${REGION}${NAME:+/$NAME}/components"; }

show_help() {
    cat << EOF
${BOLD}new-environment.sh - Environment Bootstrap Script${RESET}

Creates a new Atmos stack (<tenant>-<region code>-<stage>[-<name>], e.g.
fnx-uw2-dev) with its stack manifest and component files, then verifies the
shared state backend.

${BOLD}USAGE:${RESET}
    $0 [options]
    $0 --interactive

${BOLD}REQUIRED OPTIONS:${RESET}
    --tenant <name>           Tenant/organization name (e.g., fnx)
    --stage <name>            Stage (e.g., dev, staging, prod)
    --region <region>         AWS region (e.g., us-east-1); the stack name carries its code (ue1)

${BOLD}OPTIONAL:${RESET}
    --name <name>             Lane name, for a second stack in the same stage and region
                              (settings.context.name, e.g. perf -> fnx-ue1-dev-perf)
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

    # Create the dev stack in us-west-2 (fnx-uw2-dev)
    $0 --tenant fnx --stage dev --region us-west-2

    # Create a dev lane with a template (fnx-ue1-dev-perf)
    $0 --tenant fnx --stage dev --name perf \\
       --region us-east-1 --template microservices-platform

    # Dry run to see what would be created
    $0 --tenant fnx --stage staging --region us-east-2 --dry-run

${BOLD}FILES CREATED:${RESET}
    stacks/orgs/<tenant>/<stage>/<region>.yaml               (lane: <region>/<name>.yaml)
    stacks/orgs/<tenant>/<stage>/<region>/components/         (lane: <region>/<name>/components/)
    +-- globals.yaml        # Catalog imports, tags, environment settings
    +-- networking.yaml     # vpc/main
    +-- security.yaml       # security components (no state backend: it is shared)
    stacks/orgs/<tenant>/<stage>/_defaults.yaml, mixins/{tenant,stage,region}/  (only if missing)

${BOLD}NOTES:${RESET}
    - stacks/orgs/<tenant>/_defaults.yaml (backend, toolchain) must already exist
    - Account IDs live only in settings.account_map.full_account_map
      (stacks/orgs/<tenant>/_defaults.yaml). A new account needs \$AWS_ACCOUNT_ID
      (12 digits): the script adds it there, and fails without it
    - VPC CIDR is auto-assigned if not specified based on environment type
    - All stacks share one state backend (backend/main in fnx-ue1-core), created once with:
      atmos workflow backend-cold-start -f bootstrap

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

    NAME=$(prompt_value "Lane name (empty for the stage's own stack)" "$NAME")

    local region_options=("us-east-1" "us-east-2" "us-west-2")
    REGION=$(prompt_selection "Select AWS region:" "${region_options[@]}")

    local env_type_options=("development" "staging" "production")
    ENV_TYPE=$(prompt_selection "Select environment type:" "${env_type_options[@]}")

    TEMPLATE=$(prompt_selection "Select stack template:" "${AVAILABLE_TEMPLATES[@]}")

    VPC_CIDR=$(prompt_value "VPC CIDR block" "$(default_cidr "$ENV_TYPE")")

    echo ""
    echo -e "${BOLD}Configuration Summary:${RESET}"
    echo "  Stack:       $(this_stack)"
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
    if [[ -n "$NAME" ]]; then
        validate_name "Lane name" "$NAME" || errors=$((errors + 1))
    fi

    if [[ -z "$REGION" ]]; then
        log_error "Region is required"
        errors=$((errors + 1))
    elif [[ ! "$REGION" =~ ^[a-z]{2}-[a-z]+-[0-9]$ ]]; then
        log_error "Invalid AWS region: $REGION"
        errors=$((errors + 1))
    elif ! region_code "$REGION" >/dev/null; then
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

    # The org defaults carry the S3 backend, the Terraform toolchain pin and
    # the account map, the only place account IDs are written
    if [[ ! -f "${REPO_ROOT}/stacks/orgs/${TENANT}/_defaults.yaml" ]]; then
        log_error "Missing stacks/orgs/${TENANT}/_defaults.yaml (backend and toolchain defaults)"
        log_info "Create it first, e.g. from stacks/orgs/fnx/_defaults.yaml"
        errors=$((errors + 1))
    elif ! python3 "${SCRIPT_DIR}/account_map_entry.py" check \
            "${REPO_ROOT}/stacks/orgs/${TENANT}/_defaults.yaml" "$ACCOUNT" ${AWS_ACCOUNT_ID:+"$AWS_ACCOUNT_ID"}; then
        errors=$((errors + 1))
    fi

    [[ $errors -eq 0 ]]
}

check_existing_environment() {
    local file dir
    file="$(stack_file)"
    dir="$(components_dir)"

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
    local region_mixin="${REPO_ROOT}/stacks/mixins/region/${REGION}.yaml"
    local stage_defaults="${REPO_ROOT}/stacks/orgs/${TENANT}/${STAGE}/_defaults.yaml"
    local org_defaults="${REPO_ROOT}/stacks/orgs/${TENANT}/_defaults.yaml"

    # The account's ID goes into the account map (checked in validate_inputs);
    # a no-op when the account is already there.
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would make sure account '${ACCOUNT}' is in the account map (orgs/${TENANT}/_defaults)"
    else
        python3 "${SCRIPT_DIR}/account_map_entry.py" add "$org_defaults" "$ACCOUNT" ${AWS_ACCOUNT_ID:+"$AWS_ACCOUNT_ID"}
    fi

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

    if [[ -f "$region_mixin" ]]; then
        log_info "Region mixin already exists: mixins/region/${REGION}"
    else
        write_file "$region_mixin" << EOF
---
# ${REGION}. settings.context.environment is the region's Cloud Posse code: the
# stack name's middle part and the start of settings.prefix (tags.Environment).
import:
  - catalog/vpc/defaults

vars:
  region: ${REGION}
settings:
  context:
    environment: $(region_code "$REGION")
EOF
    fi

    if [[ -f "$stage_defaults" ]]; then
        log_info "Stage defaults already exist: orgs/${TENANT}/${STAGE}/_defaults"
    else
        write_file "$stage_defaults" << EOF
---
import:
  - orgs/${TENANT}/_defaults
  - mixins/tenant/${TENANT}
  - mixins/stage/${STAGE}

settings:
  environment:
    account: ${ACCOUNT}
    # From the account map (stacks/orgs/${TENANT}/_defaults.yaml), keyed by account.
    account_id: '{{ index .settings.account_map.full_account_map .settings.environment.account }}'
EOF
    fi
}

generate_stack_file() {
    log_step "Generating Stack Manifest"

    local name_context=""
    [[ -n "$NAME" ]] && name_context="
    name: ${NAME}"

    write_file "$(stack_file)" << EOF
---
# =============================================================================
# Stack: $(this_stack)
# =============================================================================
# Template: ${TEMPLATE}
# Environment Type: ${ENV_TYPE}
# Created by scripts/new-environment.sh on $(date -u '+%Y-%m-%d')
# =============================================================================

import:
  - catalog/_base/defaults

  # Region mixin: region and settings.context.environment (the tenant and
  # stage mixins come with the stage defaults)
  - mixins/region/${REGION}

  # Stage defaults: org defaults (backend, toolchain, account map), tenant and stage mixins, account
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
  context:
    tenant: ${TENANT}
    stage: ${STAGE}${name_context}
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

    # The one settings.environment key the generated components read
    local is_prod="false"
    [[ "$ENV_TYPE" == "production" ]] && is_prod="true"

    write_file "$(components_dir)/globals.yaml" << EOF
---
# Environment-wide settings for $(this_stack)

import:
  - catalog/vpc/defaults
  - catalog/backend/defaults
${template_import}

vars:
  tags:
    Template: "${TEMPLATE}"

settings:
  environment:
    enable_vpc_flow_logs: ${is_prod}
EOF

    write_file "$(components_dir)/networking.yaml" << EOF
---
# Networking for $(this_stack)

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
        ipv4_primary_cidr_block: "${VPC_CIDR}"
${subnets_block}
        vpc_flow_logs_enabled: "{{ .settings.environment.enable_vpc_flow_logs }}"
EOF

    write_file "$(components_dir)/security.yaml" << EOF
---
# Security components for $(this_stack).
# No state backend here: every stack uses the single backend (backend/main in
# fnx-ue1-core). Give this stack CI roles (iam/ci, see the existing stacks'
# security.yaml) and add their ARNs to that instance's access_roles entries for
# this stack's stage (read/write for dev and staging, prod_read/prod_write for prod),
# with this stack's object_key_patterns pair "*/$(this_stack)/*" and
# "*/$(this_stack)-*" (stacks/orgs/fnx/core/us-east-1.yaml).

import:
  - $(import_prefix)/globals

components:
  terraform: {}
EOF
}

validate_generated_stack() {
    [[ "$DRY_RUN" == "true" ]] && return 0

    log_step "Validating Generated Stack"

    if atmos --chdir "$REPO_ROOT" describe stacks -s "$(this_stack)" --process-functions=false >/dev/null; then
        log_success "Stack resolves: $(this_stack)"
    else
        log_error "atmos could not resolve stack $(this_stack); review the generated files"
        return 1
    fi
}

initialize_backend() {
    if [[ "$SKIP_BACKEND" == "true" ]]; then
        log_info "Skipping backend bootstrap (--skip-backend)"
        return 0
    fi

    log_step "Checking the Shared State Backend"

    # Every stack uses the single backend (backend/main in fnx-ue1-core); a new
    # stack creates none. Create it once with `atmos workflow backend-cold-start
    # -f bootstrap`; here it is only verified.
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would run: atmos workflow verify -f bootstrap"
        return 0
    fi

    atmos --chdir "$REPO_ROOT" workflow verify -f bootstrap
}

initialize_workspace() {
    if [[ "$INITIALIZE_WORKSPACE" != "true" ]]; then
        log_info "Skipping workspace initialization (--no-workspace)"
        return 0
    fi

    log_step "Initializing Terraform Workspace"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would run: atmos terraform init vpc/main -s $(this_stack)"
        return 0
    fi

    if atmos --chdir "$REPO_ROOT" terraform init vpc/main -s "$(this_stack)"; then
        log_success "Terraform initialized for stack: $(this_stack)"
    else
        log_warning "Could not initialize Terraform automatically"
        log_info "Run manually: atmos terraform init vpc/main -s $(this_stack)"
    fi
}

# ==============================================================================
# Summary and Next Steps
# ==============================================================================

show_summary() {
    log_step "Environment Created Successfully"

    echo ""
    echo -e "${BOLD}Stack Details:${RESET}"
    echo "  Stack Name:     $(this_stack)"
    echo "  Manifest:       $(stack_file)"
    echo "  Template:       $TEMPLATE"
    echo "  Environment:    $ENV_TYPE"
    echo "  Region:         $REGION"
    echo "  VPC CIDR:       $VPC_CIDR"
    echo ""

    echo -e "${BOLD}Next Steps:${RESET}"
    echo ""
    echo -e "  1. Review and customize the configuration:"
    echo -e "     ${CYAN}atmos describe stacks -s $(this_stack)${RESET}"
    echo ""
    echo -e "  2. Validate the stack:"
    echo -e "     ${CYAN}atmos workflow validate -f validate -s $(this_stack)${RESET}"
    echo ""
    echo -e "  3. Plan the deployment:"
    echo -e "     ${CYAN}atmos workflow plan -f plan-environment -s $(this_stack)${RESET}"
    echo ""
    echo -e "  4. Deploy the environment:"
    echo -e "     ${CYAN}atmos workflow full -f bootstrap -s $(this_stack)${RESET}"
    echo -e "     ${CYAN}atmos workflow deploy -f deploy-full-stack -s $(this_stack)${RESET}"
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
            --name)
                NAME="$2"
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
    if [[ "$INTERACTIVE" == "true" ]] || [[ -z "$TENANT" && -z "$STAGE" && -z "$ACCOUNT" && -z "$REGION" ]]; then
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
