#!/usr/bin/env bash
# Consolidated operations script for Atmos
# This script provides simplified access to common Atmos operations

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ANSI color codes
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;36m'
RESET='\033[0m'

# Print deprecation notice
echo -e "${YELLOW}NOTE: This script uses the Python implementation but provides a simplified interface.${RESET}"
echo -e "${YELLOW}For complete functionality, use: atmos-cli <command> [options]${RESET}"
echo ""

# Show usage information
usage() {
  echo -e "${BLUE}Usage:${RESET} $(basename "$0") <command> [options]"
  echo ""
  echo "Commands:"
  echo "  apply     - Apply components in an environment"
  echo "  plan      - Plan changes for components"
  echo "  validate  - Validate components"
  echo "  drift     - Detect infrastructure drift"
  echo "  destroy   - Destroy components"
  echo "  state     - Manage Terraform state locks"
  echo "  setup     - Set up the Python CLI environment"
  echo ""
  echo "Examples:"
  echo "  $(basename "$0") apply"
  echo "  $(basename "$0") plan"
  echo "  $(basename "$0") drift"
  echo "  $(basename "$0") state list"
  echo ""
  exit 1
}

# Check for Python CLI installation
check_cli() {
  if ! command -v "${REPO_ROOT}/bin/atmos-cli" &> /dev/null; then
    echo -e "${YELLOW}Python CLI not installed or not found.${RESET}"
    echo "Would you like to set it up now? [y/N] "
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
      "${SCRIPT_DIR}/setup.sh"
    else
      echo -e "${RED}Python CLI is required. Exiting.${RESET}"
      exit 1
    fi
  fi
}

# Get common environment variables
get_env_vars() {
  # Try to get environment variables from command line or environment
  TENANT="${tenant:-${TENANT:-}}"
  ACCOUNT="${account:-${ACCOUNT:-}}"
  ENVIRONMENT="${environment:-${ENVIRONMENT:-}}"
  
  # Prompt for missing variables
  if [[ -z "$TENANT" ]]; then
    echo -n "Enter tenant: "
    read -r TENANT
  fi
  
  if [[ -z "$ACCOUNT" ]]; then
    echo -n "Enter account: "
    read -r ACCOUNT
  fi
  
  if [[ -z "$ENVIRONMENT" ]]; then
    echo -n "Enter environment: "
    read -r ENVIRONMENT
  fi
  
  # Validate
  if [[ -z "$TENANT" || -z "$ACCOUNT" || -z "$ENVIRONMENT" ]]; then
    echo -e "${RED}Error: tenant, account, and environment are required.${RESET}"
    exit 1
  fi
  
  # Create stack name
  STACK="${TENANT}-${ACCOUNT}-${ENVIRONMENT}"
  echo -e "${GREEN}Using stack: ${STACK}${RESET}"
}

# Main function
main() {
  # Check if command provided
  if [[ $# -lt 1 ]]; then
    usage
  fi
  
  # Parse command
  COMMAND="$1"
  shift
  
  # Check for Python CLI
  check_cli
  
  # Handle commands
  case "$COMMAND" in
    apply)
      get_env_vars
      echo -e "${BLUE}Applying components for ${STACK}...${RESET}"
      "${REPO_ROOT}/bin/atmos-cli" workflow apply-environment \
        --tenant "$TENANT" \
        --account "$ACCOUNT" \
        --environment "$ENVIRONMENT" \
        --auto-approve "${auto_approve:-false}" \
        --parallel "${parallel:-false}"
      ;;
      
    plan)
      get_env_vars
      echo -e "${BLUE}Planning components for ${STACK}...${RESET}"
      "${REPO_ROOT}/bin/atmos-cli" workflow plan-environment \
        --tenant "$TENANT" \
        --account "$ACCOUNT" \
        --environment "$ENVIRONMENT" \
        --output-dir "${output_dir:-}" \
        --parallel "${parallel:-false}"
      ;;
      
    validate)
      get_env_vars
      echo -e "${BLUE}Validating components for ${STACK}...${RESET}"
      "${REPO_ROOT}/bin/atmos-cli" workflow validate \
        --tenant "$TENANT" \
        --account "$ACCOUNT" \
        --environment "$ENVIRONMENT" \
        --parallel "${parallel:-true}"
      ;;
      
    drift)
      get_env_vars
      echo -e "${BLUE}Detecting drift for ${STACK}...${RESET}"
      "${REPO_ROOT}/bin/atmos-cli" workflow drift-detection \
        --tenant "$TENANT" \
        --account "$ACCOUNT" \
        --environment "$ENVIRONMENT" \
        --parallel "${parallel:-true}"
      ;;
      
    destroy)
      get_env_vars
      echo -e "${RED}WARNING: This will destroy all components in ${STACK}${RESET}"
      echo -n "Are you sure you want to continue? [y/N] "
      read -r response
      if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Operation cancelled."
        exit 0
      fi
      
      "${REPO_ROOT}/bin/atmos-cli" workflow destroy-environment \
        --tenant "$TENANT" \
        --account "$ACCOUNT" \
        --environment "$ENVIRONMENT" \
        --auto-approve "${auto_approve:-false}" \
        --safe-destroy "${safe_destroy:-true}"
      ;;
      
    state)
      get_env_vars
      STATE_CMD="${1:-list}"
      shift || true
      
      case "$STATE_CMD" in
        list)
          "${REPO_ROOT}/bin/atmos-cli" state list-locks "$STACK"
          ;;
        detect)
          "${REPO_ROOT}/bin/atmos-cli" state detect-abandoned-locks "$STACK" --older-than "${older_than:-120}"
          ;;
        clean)
          "${REPO_ROOT}/bin/atmos-cli" state clean-abandoned-locks "$STACK" --older-than "${older_than:-120}" --force "${force:-false}"
          ;;
        *)
          echo -e "${RED}Unknown state command: ${STATE_CMD}${RESET}"
          echo "Available state commands: list, detect, clean"
          exit 1
          ;;
      esac
      ;;
      
    setup)
      "${SCRIPT_DIR}/setup.sh"
      ;;
      
    *)
      echo -e "${RED}Unknown command: ${COMMAND}${RESET}"
      usage
      ;;
  esac
}

# Run main function with all arguments
main "$@"