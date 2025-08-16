#!/usr/bin/env bash
set -euo pipefail

# Script to update tool versions in .env file
# Supports updating to latest, LTS, or specific versions

# Text formatting
BOLD="\033[1m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
RESET="\033[0m"

# Paths
ENV_FILE="$(dirname "$0")/../.env"

# Default configuration
MODE="latest"  # latest, lts, specific
TOOLS=()
VERSION=""
CHECK_ONLY=false
SHOW_ALL=false
BATCH_MODE=false

# Tool categories for batch updates (bash 3.x compatible)
# Using variables instead of associative arrays
TOOL_CATEGORY_CORE="TERRAFORM_VERSION ATMOS_VERSION KUBECTL_VERSION HELM_VERSION"
TOOL_CATEGORY_SECURITY="TFSEC_VERSION TFLINT_VERSION CHECKOV_VERSION"
TOOL_CATEGORY_AWS="AWS_CLI_VERSION SESSION_MANAGER_VERSION"
TOOL_CATEGORY_PROVIDERS="TF_PROVIDER_AWS_VERSION TF_PROVIDER_KUBERNETES_VERSION TF_PROVIDER_HELM_VERSION TF_PROVIDER_TLS_VERSION TF_PROVIDER_TIME_VERSION TF_PROVIDER_KUBECTL_VERSION"
TOOL_CATEGORY_CICD="YAMLLINT_VERSION PRECOMMIT_VERSION TERRAFORM_DOCS_VERSION"
TOOL_CATEGORY_TEMPLATING="COPIER_VERSION"
TOOL_CATEGORY_ALL="$TOOL_CATEGORY_CORE $TOOL_CATEGORY_SECURITY $TOOL_CATEGORY_AWS $TOOL_CATEGORY_PROVIDERS $TOOL_CATEGORY_CICD $TOOL_CATEGORY_TEMPLATING"

# API endpoints and patterns for version lookups (bash 3.x compatible)
# Using a lookup function instead of associative arrays
VERSION_APIS[TERRAFORM_VERSION]="https://releases.hashicorp.com/terraform/|latest_version=\\\"([0-9]+\\.[0-9]+\\.[0-9]+)\\\""
VERSION_APIS[TERRAFORM_VERSION_LTS]="https://releases.hashicorp.com/terraform/|latest_version=\\\"([0-9]+\\.[0-9]+\\.[0-9]+)\\\""
VERSION_APIS[ATMOS_VERSION]="https://api.github.com/repos/cloudposse/atmos/releases/latest|\"tag_name\":\"v([0-9]+\\.[0-9]+\\.[0-9]+)\""
VERSION_APIS[ATMOS_VERSION_LTS]="https://api.github.com/repos/cloudposse/atmos/releases/latest|\"tag_name\":\"v([0-9]+\\.[0-9]+\\.[0-9]+)\""
VERSION_APIS[KUBECTL_VERSION]="https://storage.googleapis.com/kubernetes-release/release/stable.txt|v([0-9]+\\.[0-9]+\\.[0-9]+)"
VERSION_APIS[KUBECTL_VERSION_LTS]="https://storage.googleapis.com/kubernetes-release/release/stable.txt|v([0-9]+\\.[0-9]+\\.[0-9]+)"
VERSION_APIS[HELM_VERSION]="https://api.github.com/repos/helm/helm/releases/latest|\"tag_name\":\"v([0-9]+\\.[0-9]+\\.[0-9]+)\""
VERSION_APIS[HELM_VERSION_LTS]="https://api.github.com/repos/helm/helm/releases/latest|\"tag_name\":\"v([0-9]+\\.[0-9]+\\.[0-9]+)\""
VERSION_APIS[TFSEC_VERSION]="https://api.github.com/repos/aquasecurity/tfsec/releases/latest|\"tag_name\":\"v([0-9]+\\.[0-9]+\\.[0-9]+)\""
VERSION_APIS[TFLINT_VERSION]="https://api.github.com/repos/terraform-linters/tflint/releases/latest|\"tag_name\":\"v([0-9]+\\.[0-9]+\\.[0-9]+)\""
VERSION_APIS[CHECKOV_VERSION]="https://api.github.com/repos/bridgecrewio/checkov/releases/latest|\"tag_name\":\"([0-9]+\\.[0-9]+\\.[0-9]+)\""
VERSION_APIS[AWS_CLI_VERSION]="https://raw.githubusercontent.com/aws/aws-cli/v2/CHANGELOG.rst|([0-9]+\\.[0-9]+\\.[0-9]+)"
VERSION_APIS[SESSION_MANAGER_VERSION]="https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html|([0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+)"
VERSION_APIS[YAMLLINT_VERSION]="https://api.github.com/repos/adrienverge/yamllint/releases/latest|\"tag_name\":\"v([0-9]+\\.[0-9]+\\.[0-9]+)\""
VERSION_APIS[PRECOMMIT_VERSION]="https://api.github.com/repos/pre-commit/pre-commit/releases/latest|\"tag_name\":\"v([0-9]+\\.[0-9]+\\.[0-9]+)\""
VERSION_APIS[TERRAFORM_DOCS_VERSION]="https://api.github.com/repos/terraform-docs/terraform-docs/releases/latest|\"tag_name\":\"v([0-9]+\\.[0-9]+\\.[0-9]+)\""
VERSION_APIS[COPIER_VERSION]="curl -s https://pypi.org/pypi/copier/json | jq -r '.info.version'|([0-9]+\\.[0-9]+\\.[0-9]+)"
VERSION_APIS[TF_PROVIDER_AWS_VERSION]="https://api.github.com/repos/hashicorp/terraform-provider-aws/releases/latest|\"tag_name\":\"v([0-9]+\\.[0-9]+\\.[0-9]+)\""
VERSION_APIS[TF_PROVIDER_KUBERNETES_VERSION]="https://api.github.com/repos/hashicorp/terraform-provider-kubernetes/releases/latest|\"tag_name\":\"v([0-9]+\\.[0-9]+\\.[0-9]+)\""
VERSION_APIS[TF_PROVIDER_HELM_VERSION]="https://api.github.com/repos/hashicorp/terraform-provider-helm/releases/latest|\"tag_name\":\"v([0-9]+\\.[0-9]+\\.[0-9]+)\""
VERSION_APIS[TF_PROVIDER_TLS_VERSION]="https://api.github.com/repos/hashicorp/terraform-provider-tls/releases/latest|\"tag_name\":\"v([0-9]+\\.[0-9]+\\.[0-9]+)\""
VERSION_APIS[TF_PROVIDER_TIME_VERSION]="https://api.github.com/repos/hashicorp/terraform-provider-time/releases/latest|\"tag_name\":\"v([0-9]+\\.[0-9]+\\.[0-9]+)\""
VERSION_APIS[TF_PROVIDER_KUBECTL_VERSION]="https://api.github.com/repos/gavinbunney/terraform-provider-kubectl/releases/latest|\"tag_name\":\"v([0-9]+\\.[0-9]+\\.[0-9]+)\""

# Help message
show_help() {
  echo -e "${BOLD}Version Updater for .env${RESET}"
  echo -e "This script updates tool versions in the .env file."
  echo
  echo -e "${BOLD}Usage:${RESET}"
  echo "  $0 [options] [tool_names...]"
  echo
  echo -e "${BOLD}Options:${RESET}"
  echo "  -h, --help            Show this help message"
  echo "  -l, --latest          Update to latest versions (default)"
  echo "  -s, --lts             Update to LTS versions where available"
  echo "  -v, --version VERSION Set specific version (must specify only one tool)"
  echo "  -c, --check           Check for updates without modifying .env"
  echo "  -a, --all             Show all available tools and their current versions"
  echo "  -g, --group GROUP     Update all tools in the specified group:"
  echo "                        (core, security, aws, providers, cicd, templating, all)"
  echo
  echo -e "${BOLD}Examples:${RESET}"
  echo "  $0 TERRAFORM_VERSION                     # Update Terraform to latest"
  echo "  $0 -v 1.5.7 TERRAFORM_VERSION            # Update Terraform to 1.5.7"
  echo "  $0 -l TERRAFORM_VERSION KUBECTL_VERSION  # Update Terraform and Kubectl to latest"
  echo "  $0 -g core                               # Update all core tools to latest"
  echo "  $0 -g all                                # Update all tools to latest"
  echo "  $0 -c -g all                             # Check for updates for all tools"
  echo "  $0 -a                                    # List all tools and their current versions"
  echo
}

# Get current version from .env file
get_current_version() {
  local tool=$1
  grep -E "^$tool=" "$ENV_FILE" | cut -d'=' -f2 || echo "Not set"
}

# Fetch latest version from API endpoint
fetch_latest_version() {
  local tool=$1
  local tool_key="${tool}"
  
  if [[ "$MODE" == "lts" ]]; then
    tool_key="${tool}_LTS"
  fi
  
  local api_info=""
  local pattern=""
  
  # Lookup API info based on tool (bash 3.x compatible)
  case "$tool_key" in
    "TERRAFORM_VERSION"|"TERRAFORM_VERSION_LTS")
      api_info="https://releases.hashicorp.com/terraform/"
      pattern="latest_version=\"([0-9]+\.[0-9]+\.[0-9]+)\""
      ;;
    "ATMOS_VERSION"|"ATMOS_VERSION_LTS")
      api_info="https://api.github.com/repos/cloudposse/atmos/releases/latest"
      pattern="\"tag_name\":\"v([0-9]+\.[0-9]+\.[0-9]+)\""
      ;;
    "KUBECTL_VERSION"|"KUBECTL_VERSION_LTS")
      api_info="https://storage.googleapis.com/kubernetes-release/release/stable.txt"
      pattern="v([0-9]+\.[0-9]+\.[0-9]+)"
      ;;
    "HELM_VERSION"|"HELM_VERSION_LTS")
      api_info="https://api.github.com/repos/helm/helm/releases/latest"
      pattern="\"tag_name\":\"v([0-9]+\.[0-9]+\.[0-9]+)\""
      ;;
    "TFSEC_VERSION")
      api_info="https://api.github.com/repos/aquasecurity/tfsec/releases/latest"
      pattern="\"tag_name\":\"v([0-9]+\.[0-9]+\.[0-9]+)\""
      ;;
    "TFLINT_VERSION")
      api_info="https://api.github.com/repos/terraform-linters/tflint/releases/latest"
      pattern="\"tag_name\":\"v([0-9]+\.[0-9]+\.[0-9]+)\""
      ;;
    "CHECKOV_VERSION")
      api_info="https://api.github.com/repos/bridgecrewio/checkov/releases/latest"
      pattern="\"tag_name\":\"([0-9]+\.[0-9]+\.[0-9]+)\""
      ;;
    "COPIER_VERSION")
      api_info="curl -s https://pypi.org/pypi/copier/json | jq -r '.info.version'"
      pattern="([0-9]+\.[0-9]+\.[0-9]+)"
      ;;
    *)
      echo -e "${YELLOW}No version lookup available for $tool${RESET}" >&2
      return 1
      ;;
  esac
  
  # Special handling for Copier which uses a direct command rather than a URL
  if [[ "$tool" == "COPIER_VERSION" ]]; then
    echo -e "${BLUE}Fetching latest version for $tool from PyPI...${RESET}" >&2
    local result=$(eval "$api_info")
    
    if [[ -z "$result" ]]; then
      echo -e "${YELLOW}Could not determine latest version for $tool${RESET}" >&2
      return 1
    fi
    
    echo "$result"
    return 0
  fi
  
  # Standard handling for other tools
  echo -e "${BLUE}Fetching latest version for $tool from $api_info...${RESET}" >&2
  
  local result=$(curl -s "$api_info" | grep -Eo "$pattern" | head -1 | sed -E 's/.*([0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?).*/\1/')
  
  if [[ -z "$result" ]]; then
    echo -e "${YELLOW}Could not determine latest version for $tool${RESET}" >&2
    return 1
  fi
  
  echo "$result"
}

# Update version in .env file
update_version() {
  local tool=$1
  local new_version=$2
  local current_version=$(get_current_version "$tool")
  
  if [[ "$current_version" == "$new_version" ]]; then
    echo -e "${GREEN}$tool is already at version $new_version${RESET}"
    return 0
  fi
  
  if [[ "$CHECK_ONLY" == "true" ]]; then
    if [[ "$current_version" == "Not set" ]]; then
      echo -e "${YELLOW}$tool is not set, latest version is $new_version${RESET}"
    else
      echo -e "${BLUE}$tool: $current_version → $new_version${RESET}"
    fi
    return 0
  fi
  
  if [[ "$current_version" == "Not set" ]]; then
    echo -e "${YELLOW}Adding $tool=$new_version to .env${RESET}"
    echo "$tool=$new_version" >> "$ENV_FILE"
  else
    echo -e "${GREEN}Updating $tool: $current_version → $new_version${RESET}"
    sed -i.bak -E "s/^($tool=).*/\1$new_version/" "$ENV_FILE"
    rm -f "${ENV_FILE}.bak"
  fi
}

# Process a single tool
process_tool() {
  local tool=$1
  
  # Validate tool name
  if ! grep -q "^$tool=" "$ENV_FILE" && [[ "$CHECK_ONLY" == "false" ]] && [[ "$MODE" != "specific" ]]; then
    echo -e "${YELLOW}Warning: $tool not found in .env file${RESET}"
    # Don't return an error, as we'll add it if updating
  fi
  
  if [[ "$MODE" == "specific" ]]; then
    if [[ -z "$VERSION" ]]; then
      echo -e "${RED}Error: Must specify a version with -v/--version when using specific mode${RESET}"
      return 1
    fi
    update_version "$tool" "$VERSION"
  else
    local latest_version=$(fetch_latest_version "$tool")
    if [[ -z "$latest_version" ]]; then
      return 1
    fi
    update_version "$tool" "$latest_version"
  fi
}

# Process all specified tools
process_tools() {
  local success_count=0
  local fail_count=0
  
  for tool in "${TOOLS[@]}"; do
    if process_tool "$tool"; then
      ((success_count++))
    else
      ((fail_count++))
    fi
  done
  
  echo
  echo -e "${GREEN}Successfully processed $success_count tool(s)${RESET}"
  if [[ $fail_count -gt 0 ]]; then
    echo -e "${YELLOW}Failed to process $fail_count tool(s)${RESET}"
  fi
}

# Display all tools
show_all_tools() {
  echo -e "${BOLD}Available Tools in .env:${RESET}"
  echo
  echo -e "${BOLD}Core Tools:${RESET}"
  for tool in $TOOL_CATEGORY_CORE; do
    echo -e "${BLUE}$tool${RESET}: $(get_current_version "$tool")"
  done
  
  echo
  echo -e "${BOLD}Security Tools:${RESET}"
  for tool in $TOOL_CATEGORY_SECURITY; do
    echo -e "${BLUE}$tool${RESET}: $(get_current_version "$tool")"
  done
  
  echo
  echo -e "${BOLD}AWS Tools:${RESET}"
  for tool in $TOOL_CATEGORY_AWS; do
    echo -e "${BLUE}$tool${RESET}: $(get_current_version "$tool")"
  done
  
  echo
  echo -e "${BOLD}Terraform Providers:${RESET}"
  for tool in $TOOL_CATEGORY_PROVIDERS; do
    echo -e "${BLUE}$tool${RESET}: $(get_current_version "$tool")"
  done
  
  echo
  echo -e "${BOLD}CI/CD Tools:${RESET}"
  for tool in $TOOL_CATEGORY_CICD; do
    echo -e "${BLUE}$tool${RESET}: $(get_current_version "$tool")"
  done
  
  echo
  echo -e "${BOLD}Templating Tools:${RESET}"
  for tool in $TOOL_CATEGORY_TEMPLATING; do
    echo -e "${BLUE}$tool${RESET}: $(get_current_version "$tool")"
  done
  
  echo
  echo -e "Use ${YELLOW}$0 <tool_name>${RESET} to update a specific tool or ${YELLOW}$0 -g <group>${RESET} to update a group of tools."
}

# Parse command line options
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      show_help
      exit 0
      ;;
    -l|--latest)
      MODE="latest"
      shift
      ;;
    -s|--lts)
      MODE="lts"
      shift
      ;;
    -v|--version)
      MODE="specific"
      VERSION="$2"
      shift 2
      ;;
    -c|--check)
      CHECK_ONLY=true
      shift
      ;;
    -a|--all)
      SHOW_ALL=true
      shift
      ;;
    -g|--group)
      BATCH_MODE=true
      local group="$2"
      local tools_string=""
      
      case "$group" in
        "core")
          tools_string="$TOOL_CATEGORY_CORE"
          ;;
        "security")
          tools_string="$TOOL_CATEGORY_SECURITY"
          ;;
        "aws")
          tools_string="$TOOL_CATEGORY_AWS"
          ;;
        "providers")
          tools_string="$TOOL_CATEGORY_PROVIDERS"
          ;;
        "cicd")
          tools_string="$TOOL_CATEGORY_CICD"
          ;;
        "templating")
          tools_string="$TOOL_CATEGORY_TEMPLATING"
          ;;
        "all")
          tools_string="$TOOL_CATEGORY_ALL"
          ;;
        *)
          echo -e "${RED}Error: Unknown group '$group'. Available groups: core, security, aws, providers, cicd, templating, all${RESET}"
          exit 1
          ;;
      esac
      
      # Split the string into array (bash 3.x compatible)
      IFS=' ' read -ra TOOLS <<< "$tools_string"
      shift 2
      ;;
    -*)
      echo -e "${RED}Unknown option: $1${RESET}"
      show_help
      exit 1
      ;;
    *)
      TOOLS+=("$1")
      shift
      ;;
  esac
done

# Validate inputs
if [[ ! -f "$ENV_FILE" ]]; then
  echo -e "${RED}Error: .env file not found at $ENV_FILE${RESET}"
  exit 1
fi

if [[ "$SHOW_ALL" == "true" ]]; then
  show_all_tools
  exit 0
fi

if [[ ${#TOOLS[@]} -eq 0 && "$BATCH_MODE" == "false" ]]; then
  echo -e "${YELLOW}No tools specified. Use -h/--help for usage information.${RESET}"
  echo -e "${YELLOW}Use -a/--all to see all available tools.${RESET}"
  exit 1
fi

if [[ "$MODE" == "specific" && ${#TOOLS[@]} -gt 1 ]]; then
  echo -e "${RED}Error: Can only specify one tool when using specific version (-v/--version)${RESET}"
  exit 1
fi

# Execute the update
process_tools

# Summary output
if [[ "$CHECK_ONLY" == "true" ]]; then
  echo -e "${BLUE}No changes were made to .env (check-only mode)${RESET}"
else
  echo -e "${GREEN}Updated .env successfully${RESET}"
fi