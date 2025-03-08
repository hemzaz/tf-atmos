#!/usr/bin/env bash

# Certificate Utilities
# Common functions for certificate-related scripts

# Text formatting
BOLD="\033[1m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
RESET="\033[0m"

# Function to check requirements
function check_requirements {
  local MISSING_REQS=false
  
  echo -e "${BLUE}Checking requirements...${RESET}"
  
  if ! command -v ssh-keygen &> /dev/null; then
    echo -e "${RED}✘ ssh-keygen is not installed. Please install OpenSSH.${RESET}"
    MISSING_REQS=true
  else
    echo -e "${GREEN}✓ ssh-keygen is installed${RESET}"
  fi
  
  if ! command -v aws &> /dev/null; then
    echo -e "${RED}✘ AWS CLI is not installed. Please install it: https://aws.amazon.com/cli/${RESET}"
    MISSING_REQS=true
  else
    echo -e "${GREEN}✓ AWS CLI is installed${RESET}"
  fi
  
  if ! command -v jq &> /dev/null; then
    echo -e "${RED}✘ jq is not installed. Please install it: brew install jq / apt install jq${RESET}"
    MISSING_REQS=true
  else
    echo -e "${GREEN}✓ jq is installed${RESET}"
  fi
  
  if [[ "$MISSING_REQS" == "true" ]]; then
    echo -e "${RED}Please install missing requirements and try again.${RESET}"
    exit 1
  fi
}

# Function to validate AWS credentials
function validate_aws_credentials {
  echo -e "${BLUE}Validating AWS credentials...${RESET}"
  
  if ! aws sts get-caller-identity --profile "$PROFILE" &> /dev/null; then
    echo -e "${RED}✘ AWS credentials are not valid or not configured for profile ${PROFILE}.${RESET}"
    echo -e "${YELLOW}Please run 'aws configure --profile ${PROFILE}' or set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment variables.${RESET}"
    exit 1
  else
    local IDENTITY=$(aws sts get-caller-identity --profile "$PROFILE" --query 'Arn' --output text)
    echo -e "${GREEN}✓ AWS credentials are valid${RESET}"
    echo -e "  Authenticated as: ${IDENTITY}"
    echo -e "  Region: ${REGION}"
  fi
}

# Function to create a secure temporary directory
function create_temp_dir {
  local TEMP_DIR=$(mktemp -d)
  chmod 700 "$TEMP_DIR"
  echo "$TEMP_DIR"
}

# Function to securely remove temporary files
function cleanup_temp_files {
  local DIR_TO_REMOVE="$1"
  if [[ -d "$DIR_TO_REMOVE" ]]; then
    rm -rf "$DIR_TO_REMOVE"
  fi
}