#!/usr/bin/env bash
# Configuration management for Atmos scripts
# DEPRECATED: Use the Python implementation in atmos_cli/config.py instead

# Print deprecation notice - only in interactive mode
if [[ -t 1 ]]; then
  echo "⚠️  DEPRECATION NOTICE: This config.sh script is deprecated."
  echo "Please use the Python implementation in atmos_cli/config.py for new code."
fi

# Ensure script is sourced not executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Error: This script should be sourced, not executed."
  exit 1
fi

# Source logger if not already available
if [[ -z "$(type -t log_info)" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -f "${SCRIPT_DIR}/logger.sh" ]]; then
    source "${SCRIPT_DIR}/logger.sh"
  else
    echo "Warning: logger.sh not found. Logging functions will not be available."
  fi
fi

# Default tool versions
# These can be overridden in .atmos.env or ATMOS_CONFIG_FILE
TERRAFORM_VERSION="1.5.7"
ATMOS_VERSION="1.38.0"
KUBECTL_VERSION="1.28.3"
HELM_VERSION="3.13.1"
TFSEC_VERSION="1.28.13"
TFLINT_VERSION="0.55.1"
CHECKOV_VERSION="3.2.382"
COPIER_VERSION="9.5.0"
TERRAFORM_DOCS_VERSION="0.16.0"

# Directory configuration
COMPONENTS_DIR="components/terraform"
SCRIPTS_DIR="scripts"
WORKFLOWS_DIR="workflows"
STACKS_BASE_DIR="stacks"

# Find the repository root directory
get_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

# Configuration file search paths (in order of precedence)
find_config_files() {
  local repo_root="$(get_repo_root)"
  local config_paths=(
    # Explicit environment variable 
    "${ATMOS_CONFIG_FILE}"
    # Project-specific configs
    "${repo_root}/.atmos.env"
    "${repo_root}/.env"
    # User-specific configs
    "${HOME}/.atmos/config"
    "${HOME}/.config/atmos/config"
  )
  
  local found_configs=()
  
  for config_path in "${config_paths[@]}"; do
    if [[ -f "${config_path}" ]]; then
      found_configs+=("${config_path}")
    fi
  done
  
  # Return the found config files as a space-separated list
  echo "${found_configs[*]}"
}

# Load configuration from files
load_config() {
  local config_files=($(find_config_files))
  
  if [[ ${#config_files[@]} -gt 0 ]]; then
    # First load defaults from all config files in reverse order (lowest precedence first)
    local reversed_configs=()
    for ((i=${#config_files[@]}-1; i>=0; i--)); do
      reversed_configs+=("${config_files[i]}")
    done
    
    for config_file in "${reversed_configs[@]}"; do
      if [[ -n "$(type -t log_info)" ]]; then
        log_info "Loading configuration from ${config_file}"
      else
        echo "Loading configuration from ${config_file}"
      fi
      
      source "${config_file}"
    done
    return 0
  else
    if [[ -n "$(type -t log_warn)" ]]; then
      log_warn "No configuration files found. Using default values."
    else
      echo "Warning: No configuration files found. Using default values."
    fi
    return 1
  fi
}

# Initialize configuration
init_config() {
  # Always try to load config file first
  load_config
  
  # Then override with environment variables if present
  TERRAFORM_VERSION="${TERRAFORM_VERSION:-1.5.7}"
  ATMOS_VERSION="${ATMOS_VERSION:-1.38.0}"
  KUBECTL_VERSION="${KUBECTL_VERSION:-1.28.3}"
  HELM_VERSION="${HELM_VERSION:-3.13.1}"
  TFSEC_VERSION="${TFSEC_VERSION:-1.28.13}"
  TFLINT_VERSION="${TFLINT_VERSION:-0.55.1}"
  CHECKOV_VERSION="${CHECKOV_VERSION:-3.2.382}"
  COPIER_VERSION="${COPIER_VERSION:-9.5.0}"
  TERRAFORM_DOCS_VERSION="${TERRAFORM_DOCS_VERSION:-0.16.0}"
  
  # Directory configuration (with repo-relative paths)
  local repo_root="$(get_repo_root)"
  COMPONENTS_DIR="${COMPONENTS_DIR:-components/terraform}"
  COMPONENTS_DIR="${repo_root}/${COMPONENTS_DIR}"
  
  SCRIPTS_DIR="${SCRIPTS_DIR:-scripts}"
  SCRIPTS_DIR="${repo_root}/${SCRIPTS_DIR}"
  
  WORKFLOWS_DIR="${WORKFLOWS_DIR:-workflows}"
  WORKFLOWS_DIR="${repo_root}/${WORKFLOWS_DIR}"
  
  STACKS_BASE_DIR="${STACKS_BASE_DIR:-stacks}"
  STACKS_BASE_DIR="${repo_root}/${STACKS_BASE_DIR}"
  
  # Export all variables so they're available to subprocesses
  export TERRAFORM_VERSION
  export ATMOS_VERSION
  export KUBECTL_VERSION
  export HELM_VERSION
  export TFSEC_VERSION
  export TFLINT_VERSION
  export CHECKOV_VERSION
  export COPIER_VERSION
  export TERRAFORM_DOCS_VERSION
  
  export COMPONENTS_DIR
  export SCRIPTS_DIR
  export WORKFLOWS_DIR
  export STACKS_BASE_DIR
  
  # Additional exports for components
  export TERRAFORM_COMPONENTS_DIR="${COMPONENTS_DIR}"
  
  if [[ -n "$(type -t log_debug)" ]]; then
    log_debug "Configuration initialized:"
    log_debug "  TERRAFORM_VERSION: ${TERRAFORM_VERSION}"
    log_debug "  ATMOS_VERSION: ${ATMOS_VERSION}"
    log_debug "  COMPONENTS_DIR: ${COMPONENTS_DIR}"
    log_debug "  SCRIPTS_DIR: ${SCRIPTS_DIR}"
    log_debug "  WORKFLOWS_DIR: ${WORKFLOWS_DIR}"
    log_debug "  STACKS_BASE_DIR: ${STACKS_BASE_DIR}"
  fi
}

# Get environment directory for a given tenant/account/environment
get_env_dir() {
  local tenant="$1"
  local account="$2"
  local environment="$3"
  
  if [[ -z "${tenant}" || -z "${account}" || -z "${environment}" ]]; then
    if [[ -n "$(type -t log_error)" ]]; then
      log_error "Missing required parameters for get_env_dir: tenant, account, environment"
    else
      echo "Error: Missing required parameters for get_env_dir: tenant, account, environment" >&2
    fi
    return 1
  fi
  
  local env_dir="${STACKS_BASE_DIR}/${tenant}/${account}/${environment}"
  
  # Verify directory exists
  if [[ ! -d "${env_dir}" ]]; then
    if [[ -n "$(type -t log_error)" ]]; then
      log_error "Environment directory does not exist: ${env_dir}"
    else
      echo "Error: Environment directory does not exist: ${env_dir}" >&2
    fi
    return 1
  fi
  
  echo "${env_dir}"
}

# Check if installed CLI versions match required versions
check_cli_versions() {
  # Check Atmos version
  if command -v atmos >/dev/null 2>&1; then
    local installed_atmos_version=$(atmos version | sed -n 's/.*Atmos \([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p')
    if [[ -n "$(type -t log_info)" ]]; then
      log_info "Using Atmos CLI version: ${installed_atmos_version}"
    else
      echo "Using Atmos CLI version: ${installed_atmos_version}"
    fi
    
    if [[ "${installed_atmos_version}" != "${ATMOS_VERSION}" ]]; then
      if [[ -n "$(type -t log_warn)" ]]; then
        log_warn "Installed Atmos version (${installed_atmos_version}) doesn't match required version (${ATMOS_VERSION})"
      else
        echo "Warning: Installed Atmos version (${installed_atmos_version}) doesn't match required version (${ATMOS_VERSION})"
      fi
    fi
  fi
  
  # Additional CLI tool checks can be added here
}

# Main initialization function
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  # Only run init when sourced, not when executed directly
  init_config
  # Check CLI versions after initialization
  check_cli_versions
fi