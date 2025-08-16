#!/usr/bin/env bash
# Common utility functions for Atmos scripts
# DEPRECATED: Use the Python implementation in atmos_cli/utils.py instead

# Print deprecation notice - only in interactive mode and if not sourced
if [[ -t 1 && "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "⚠️  DEPRECATION NOTICE: This utils.sh script is deprecated."
  echo "Please use the Python implementation in atmos_cli/utils.py for new code."
fi

# Text formatting
BOLD="\033[1m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
RESET="\033[0m"

# Get the repository root directory
get_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

# Load environment variables from .env file
load_env_file() {
  local repo_root="${1:-$(get_repo_root)}"
  local env_file="${repo_root}/.env"
  
  if [[ -f "${env_file}" ]]; then
    echo -e "${BLUE}Loading tool versions from .env file...${RESET}"
    source "${env_file}"
    return 0
  else
    echo -e "${YELLOW}No .env file found at ${env_file}. Using default versions.${RESET}"
    # Set default versions if not already set
    TERRAFORM_VERSION="${TERRAFORM_VERSION:-1.5.7}"
    ATMOS_VERSION="${ATMOS_VERSION:-1.38.0}"
    KUBECTL_VERSION="${KUBECTL_VERSION:-1.28.3}"
    HELM_VERSION="${HELM_VERSION:-3.13.1}"
    TFSEC_VERSION="${TFSEC_VERSION:-1.28.13}"
    TFLINT_VERSION="${TFLINT_VERSION:-0.55.1}"
    CHECKOV_VERSION="${CHECKOV_VERSION:-3.2.382}"
    COPIER_VERSION="${COPIER_VERSION:-9.5.0}"
    return 1
  fi
}

# Verify Copier installation with proper version check
verify_copier_installation() {
  local required_version="${1:-${COPIER_VERSION:-9.5.0}}"
  
  if ! command -v copier &> /dev/null; then
    echo -e "${YELLOW}Copier not found. Installing...${RESET}"
    pip install "copier>=${required_version}"
    return $?
  else
    local installed_version=$(copier --version | cut -d' ' -f2)
    echo -e "${GREEN}Using installed Copier version: ${installed_version}${RESET}"
    
    # Compare versions correctly using sort -V
    if ! [[ "$(printf '%s\n' "$required_version" "$installed_version" | sort -V | head -n1)" = "$required_version" ]]; then
      echo -e "${YELLOW}WARNING: Recommended minimum Copier version is ${required_version}, but found ${installed_version}${RESET}"
      echo -e "${YELLOW}Consider upgrading: pip install \"copier>=${required_version}\"${RESET}"
    fi
    return 0
  fi
}

# AWS API retry wrapper with exponential backoff
# 
# This function addresses the ISSUES.md item:
# "No retry mechanism for AWS API calls - Makes operations brittle in environments with API rate limits"
#
# It implements a retry mechanism with:
# - Configurable maximum attempts
# - Exponential backoff with jitter
# - Smart error detection for retryable vs. non-retryable errors
# - Detailed logging of retry attempts
#
# Usage: aws_with_retry [max_attempts] [initial_sleep] [command...]
# 
# Example: 
#   aws_with_retry 5 1 aws s3 cp my-file.txt s3://my-bucket/
#   aws_with_retry 3 2 aws secretsmanager get-secret-value --secret-id my-secret
#
# Retryable errors include:
# - RequestLimitExceeded
# - ThrottlingException
# - Throttling
# - RequestThrottled
# - TooManyRequestsException
# - ServiceUnavailable
# - InternalFailure
# - Connection timeouts
#
aws_with_retry() {
  local max_attempts="${1:-5}"  # Default to 5 attempts
  local initial_sleep="${2:-1}" # Default to 1 second initial sleep
  local attempt=1
  local sleep_time=$initial_sleep
  local exit_code=0
  local output=""
  
  # Remove the first two arguments (max_attempts and initial_sleep)
  shift 2
  
  # The remaining arguments form the AWS command to execute
  local cmd=("$@")
  
  # Start retry loop
  while (( attempt <= max_attempts )); do
    # Display attempt information for verbose output
    if [[ $attempt -gt 1 ]]; then
      echo -e "${YELLOW}Retry attempt $attempt of $max_attempts for command: ${cmd[*]}${RESET}" >&2
    fi
    
    # Execute the command and capture output and exit code
    output=$("${cmd[@]}" 2>&1)
    exit_code=$?
    
    # Check if command succeeded
    if [[ $exit_code -eq 0 ]]; then
      # Command succeeded, output the result and return success
      echo "$output"
      return 0
    fi
    
    # If this was the last attempt, return the failure
    if [[ $attempt -eq $max_attempts ]]; then
      echo -e "${RED}Command failed after $max_attempts attempts: ${cmd[*]}${RESET}" >&2
      echo -e "${RED}Last error: $output${RESET}" >&2
      return $exit_code
    fi
    
    # Check for various AWS error types that are retryable
    if echo "$output" | grep -q -e "RequestLimitExceeded" -e "ThrottlingException" -e "Throttling" \
                              -e "RequestThrottled" -e "TooManyRequestsException" \
                              -e "ServiceUnavailable" -e "InternalFailure" -e "InternalError" \
                              -e "500 Internal Server Error" -e "Connection timed out"; then
      echo -e "${YELLOW}Retryable AWS error detected: $(echo "$output" | grep -o -e "RequestLimitExceeded.*" -e "ThrottlingException.*" -e "Throttling.*" -e "TooManyRequestsException.*" | head -1)${RESET}" >&2
    else
      # Non-retryable error, return immediately
      echo -e "${RED}Non-retryable error: $output${RESET}" >&2
      return $exit_code
    fi
    
    # Calculate sleep time with exponential backoff (2^attempt * initial_sleep) + random jitter
    sleep_time=$(( (2 ** (attempt - 1)) * initial_sleep + (RANDOM % initial_sleep) ))
    echo -e "${YELLOW}Waiting ${sleep_time}s before retrying...${RESET}" >&2
    sleep $sleep_time
    
    # Increment attempt counter
    (( attempt++ ))
  done
  
  # This should never be reached due to the returns in the loop
  echo "$output"
  return $exit_code
}

# Validate AWS credentials
validate_aws_credentials() {
  echo -e "${BLUE}Validating AWS credentials...${RESET}"
  if ! command -v aws >/dev/null; then
    echo -e "${YELLOW}AWS CLI not installed. Authentication will not be validated.${RESET}"
    return 1
  fi
  
  # Use retry mechanism for credential validation
  if aws_with_retry 3 1 aws sts get-caller-identity >/dev/null 2>&1; then
    echo -e "${GREEN}AWS credentials valid!${RESET}"
    return 0
  else
    echo -e "${RED}AWS credentials invalid or not configured.${RESET}"
    return 1
  fi
}

# Get AWS region with fallbacks
get_aws_region() {
  local default_region="${1:-us-west-2}"
  local region=""
  
  # Try to get the default region from AWS config
  if [ -n "$AWS_REGION" ]; then
    region="$AWS_REGION"
  elif [ -n "$AWS_DEFAULT_REGION" ]; then
    region="$AWS_DEFAULT_REGION"
  elif command -v aws >/dev/null; then
    # Use retry mechanism for region retrieval
    region=$(aws_with_retry 3 1 aws configure get region 2>/dev/null)
  fi
  
  # Default if we can't detect it
  if [ -z "$region" ]; then
    region="$default_region"
    echo -e "${YELLOW}Could not determine AWS region, using default: ${region}${RESET}"
  else
    echo -e "${BLUE}Using AWS region: ${region}${RESET}"
  fi
  
  echo "$region"
}

# Determine availability zones for a region
get_availability_zones() {
  local region="${1:-$(get_aws_region)}"
  local max_zones="${2:-3}"
  local availability_zones=""
  
  echo -e "${BLUE}Determining availability zones for region ${region}...${RESET}"
  
  if command -v aws >/dev/null && validate_aws_credentials >/dev/null 2>&1; then
    # Try to get actual availability zones from AWS if the AWS CLI is available
    # Use retry mechanism for AZ retrieval with 3 attempts and 2 second initial delay
    if AZ_LIST=$(aws_with_retry 3 2 aws ec2 describe-availability-zones --region "${region}" \
                   --query "AvailabilityZones[?State=='available'].ZoneName" \
                   --output text); then
      # Convert the list to an array and format for JSON
      local AZ_ARRAY=()
      for az in ${AZ_LIST}; do
        AZ_ARRAY+=("\"${az}\"")
      done
      
      # Take first N AZs or fewer if less are available
      local AZ_COUNT=${#AZ_ARRAY[@]}
      AZ_COUNT=$(( AZ_COUNT > max_zones ? max_zones : AZ_COUNT ))
      
      availability_zones="["
      for ((i=0; i<AZ_COUNT; i++)); do
        availability_zones+="${AZ_ARRAY[$i]}"
        if [[ $i -lt $((AZ_COUNT-1)) ]]; then
          availability_zones+=", "
        fi
      done
      availability_zones+="]"
      
      echo -e "${GREEN}Using actual AZs: ${availability_zones}${RESET}"
    else
      # Fallback to pattern if AWS CLI fails
      echo -e "${YELLOW}Could not fetch AZs from AWS, using fallback pattern${RESET}"
      availability_zones="[\"${region}a\", \"${region}b\", \"${region}c\"]"
    fi
  else
    # Fallback to pattern if AWS CLI is not available
    echo -e "${YELLOW}AWS CLI not available or credentials invalid, using fallback pattern${RESET}"
    availability_zones="[\"${region}a\", \"${region}b\", \"${region}c\"]"
  fi
  
  echo "$availability_zones"
}

# Create a secure temporary file
create_secure_temp_file() {
  local temp_file=$(mktemp)
  chmod 600 "$temp_file"
  echo "$temp_file"
}

# Validate CIDR format
validate_cidr() {
  local cidr="$1"
  if [[ $cidr =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
    return 0
  else
    echo -e "${RED}Error: Invalid CIDR format. Expected format: x.x.x.x/y (e.g., 10.0.0.0/16)${RESET}"
    return 1
  fi
}

# Validate environment name
validate_env_name() {
  local env_name="$1"
  local strict="${2:-false}"
  
  # Basic validation - must be valid identifier
  if ! [[ $env_name =~ ^[a-zA-Z0-9][a-zA-Z0-9\-]*$ ]]; then
    echo -e "${RED}Error: Environment name must be a valid identifier starting with a letter or number${RESET}"
    return 1
  fi
  
  # Pattern validation - recommended to follow name-## pattern
  if ! [[ $env_name =~ ^[a-z0-9]+-[0-9]{2}$ ]]; then
    echo -e "${YELLOW}Warning: Environment name should follow pattern: name-## for consistency${RESET}"
    
    # If in strict mode, return error
    if [[ "$strict" == "true" ]]; then
      return 1
    fi
    
    # Check if running in CI/CD environment
    local is_ci=$(is_ci_environment)
    
    # In interactive mode, ask for confirmation
    if [[ -t 0 && "$is_ci" == "false" ]]; then
      echo -n "Continue anyway? (y/n): "
      read -r response
      if [[ "$response" != "y" ]]; then
        return 1
      fi
    else
      echo -e "${YELLOW}Running in non-interactive mode, continuing despite warning...${RESET}"
    fi
  fi
  
  return 0
}

# Check if running in a CI/CD environment
is_ci_environment() {
  if [[ -n "${CI}" || -n "${GITHUB_ACTIONS}" || -n "${GITLAB_CI}" || -n "${TF_BUILD}" ]]; then
    echo "true"
  else
    echo "false"
  fi
}

# Validate email format
validate_email() {
  local email="$1"
  
  if [[ $email =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    return 0
  else
    echo -e "${RED}Error: Invalid email format: ${email}${RESET}"
    return 1
  fi
}

# Ensure directory exists
ensure_directory() {
  local dir="$1"
  local force="${2:-false}"
  
  if [[ -d "$dir" ]]; then
    if [[ -n "$(ls -A "$dir" 2>/dev/null)" ]]; then
      echo -e "${YELLOW}Warning: Directory exists and is not empty: $dir${RESET}"
      
      if [[ "$force" == "true" ]]; then
        echo -e "${YELLOW}Force option specified, removing existing directory${RESET}"
        rm -rf "$dir"
        mkdir -p "$dir"
      else
        # In interactive mode, ask for confirmation
        if [[ -t 0 && "$(is_ci_environment)" == "false" ]]; then
          echo -n "Remove existing directory? (y/n): "
          read -r response
          if [[ "$response" == "y" ]]; then
            rm -rf "$dir"
            mkdir -p "$dir"
          else
            echo -e "${RED}Aborting to prevent overwriting existing files${RESET}"
            return 1
          fi
        else
          echo -e "${RED}Directory exists. Use force=true to overwrite in non-interactive mode${RESET}"
          return 1
        fi
      fi
    fi
  else
    mkdir -p "$dir"
  fi
  
  return 0
}

# Check AWS CLI version and installation
check_aws_cli() {
  local min_version="${1:-2.0.0}"
  
  if ! command -v aws >/dev/null; then
    echo -e "${YELLOW}AWS CLI not installed${RESET}"
    return 1
  fi
  
  local version=$(aws --version 2>&1 | grep -o "aws-cli/[0-9]*\.[0-9]*\.[0-9]*" | cut -d/ -f2)
  
  if [[ -z "$version" ]]; then
    echo -e "${YELLOW}Could not determine AWS CLI version${RESET}"
    return 1
  fi
  
  echo -e "${GREEN}AWS CLI version ${version} installed${RESET}"
  
  # Compare versions
  if ! [[ "$(printf '%s\n' "$min_version" "$version" | sort -V | head -n1)" = "$min_version" ]]; then
    echo -e "${YELLOW}WARNING: Recommended minimum AWS CLI version is ${min_version}, but found ${version}${RESET}"
  fi
  
  return 0
}

# Validate path for safety
validate_path() {
  local path="$1"
  local base_dir="${2:-$(get_repo_root)}"
  local allow_outside="${3:-false}"
  
  # Check if path is empty
  if [[ -z "$path" ]]; then
    echo -e "${RED}Error: Path cannot be empty${RESET}"
    return 1
  fi
  
  # Normalize path (resolve .. and .)
  local real_path=$(realpath -m "$path")
  local real_base=$(realpath -m "$base_dir")
  
  # Check if path contains suspicious characters
  if [[ "$path" =~ [[:cntrl:]\&\;\`\$\\\|\{\}\<\>] ]]; then
    echo -e "${RED}Error: Path contains invalid characters: $path${RESET}"
    return 1
  fi
  
  # Check if path exists
  if [[ ! -e "$real_path" ]]; then
    echo -e "${YELLOW}Warning: Path does not exist: $real_path${RESET}"
    # Don't fail if path doesn't exist - this function only validates path format
    # The caller should check existence if needed
  fi
  
  # Check path traversal (if not allowing outside paths)
  if [[ "$allow_outside" != "true" && "$real_path" != "$real_base"* ]]; then
    echo -e "${RED}Error: Path is outside of base directory: $real_path${RESET}"
    echo -e "${RED}Base directory: $real_base${RESET}"
    return 1
  fi
  
  return 0
}

# Detect operating system and architecture
detect_os_and_arch() {
  local os=""
  local arch=""
  
  # Detect OS
  case "$OSTYPE" in
    linux*)
      os="linux"
      ;;
    darwin*)
      os="darwin"
      ;;
    *)
      echo -e "${RED}Unsupported operating system: $OSTYPE${RESET}"
      return 1
      ;;
  esac
  
  # Detect architecture
  local uname_arch=$(uname -m)
  case "$uname_arch" in
    x86_64)
      arch="amd64"
      ;;
    arm64|aarch64)
      arch="arm64"
      ;;
    *)
      echo -e "${RED}Unsupported architecture: $uname_arch${RESET}"
      return 1
      ;;
  esac
  
  echo -e "${GREEN}Detected OS: $os, Architecture: $arch${RESET}"
  echo "$os:$arch"
}