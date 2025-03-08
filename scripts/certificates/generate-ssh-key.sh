#!/usr/bin/env bash
set -e

# SSH Key Generation Script
# This script generates SSH keys and stores them in AWS Secrets Manager

# Import common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/certificate-utils.sh"

# Default values
KEY_TYPE="rsa"
KEY_BITS=4096
KEY_NAME=""
SECRET_NAME=""
ENVIRONMENT=""
INSTANCE_ID=""
REGION=""
PROFILE="default"
FORCE=false
OUTPUT_DIR="./generated-keys"

# Display usage information
function show_usage {
  echo -e "${BOLD}SSH Key Generation Script${RESET}"
  echo -e "Generates SSH keys and stores them in AWS Secrets Manager"
  echo
  echo -e "${BOLD}Usage:${RESET}"
  echo -e "  $0 [options]"
  echo
  echo -e "${BOLD}Options:${RESET}"
  echo -e "  -t, --type TYPE       Key type (rsa or ed25519, default: rsa)"
  echo -e "  -b, --bits BITS       Key size in bits (for RSA keys, default: 4096)"
  echo -e "  -n, --name NAME       Name for the key (required)"
  echo -e "  -e, --env ENV         Environment name (required for environment-wide keys)"
  echo -e "  -i, --instance INST   Instance ID (required for instance-specific keys)"
  echo -e "  -s, --secret SECRET   AWS Secrets Manager secret name (default: ssh-key/<env>/<name>)"
  echo -e "  -r, --region REGION   AWS region (default: current AWS CLI region)"
  echo -e "  -p, --profile PROFILE AWS profile (default: default)"
  echo -e "  -o, --output DIR      Output directory for key files (default: ./generated-keys)"
  echo -e "  -f, --force           Force overwrite if files or secret exists"
  echo -e "  -h, --help            Show this help"
  echo
  echo -e "${BOLD}Examples:${RESET}"
  echo -e "  # Generate environment-wide key"
  echo -e "  $0 -t rsa -b 4096 -n app-servers -e prod"
  echo
  echo -e "  # Generate instance-specific key"
  echo -e "  $0 -t ed25519 -n bastion -i i-0123456789abcdef0 -r us-west-2"
  echo
  exit 1
}

# Function check_requirements now imported from certificate-utils.sh

# Function to validate inputs
function validate_inputs {
  # Validate key type
  if [[ "$KEY_TYPE" != "rsa" && "$KEY_TYPE" != "ed25519" ]]; then
    echo -e "${RED}Error: Key type must be either 'rsa' or 'ed25519'.${RESET}"
    exit 1
  fi
  
  # Validate key bits (only applicable for RSA)
  if [[ "$KEY_TYPE" == "rsa" ]]; then
    if [[ "$KEY_BITS" -lt 2048 || "$KEY_BITS" -gt 8192 ]]; then
      echo -e "${RED}Error: RSA key bits must be between 2048 and 8192.${RESET}"
      exit 1
    fi
  fi
  
  # Key name is required
  if [[ -z "$KEY_NAME" ]]; then
    echo -e "${RED}Error: Key name is required. Use -n or --name.${RESET}"
    show_usage
  fi
  
  # Either environment or instance ID is required
  if [[ -z "$ENVIRONMENT" && -z "$INSTANCE_ID" ]]; then
    echo -e "${RED}Error: Either environment (-e) or instance ID (-i) is required.${RESET}"
    show_usage
  fi
  
  # Validate environment format if provided
  if [[ -n "$ENVIRONMENT" ]]; then
    # Check for valid environment name format (e.g., prod, staging, dev, etc.)
    if [[ ! "$ENVIRONMENT" =~ ^[a-zA-Z0-9_-]+$ ]]; then
      echo -e "${RED}Error: Environment name can only contain alphanumeric characters, hyphens, and underscores.${RESET}"
      exit 1
    fi
    
    # Enforce minimum length
    if [[ ${#ENVIRONMENT} -lt 2 ]]; then
      echo -e "${RED}Error: Environment name must be at least 2 characters long.${RESET}"
      exit 1
    fi
  fi
  
  # If both are provided, clarify which one to use
  if [[ -n "$ENVIRONMENT" && -n "$INSTANCE_ID" ]]; then
    echo -e "${YELLOW}Both environment and instance ID provided. This key will be associated with instance ${INSTANCE_ID} in environment ${ENVIRONMENT}.${RESET}"
  fi
  
  # If region not provided, use AWS CLI default
  if [[ -z "$REGION" ]]; then
    REGION=$(aws configure get region --profile "$PROFILE")
    if [[ -z "$REGION" ]]; then
      echo -e "${RED}Error: AWS region not specified and not found in AWS CLI config.${RESET}"
      exit 1
    fi
  fi
  
  # Set default secret name if not provided
  if [[ -z "$SECRET_NAME" ]]; then
    if [[ -n "$INSTANCE_ID" ]]; then
      SECRET_NAME="ssh-key/instance/${INSTANCE_ID}/${KEY_NAME}"
    else
      SECRET_NAME="ssh-key/${ENVIRONMENT}/global-keys/${KEY_NAME}"
    fi
  fi
  
  echo -e "${BLUE}Using parameters:${RESET}"
  echo -e "  Key Type:       ${KEY_TYPE}"
  if [[ "$KEY_TYPE" == "rsa" ]]; then
    echo -e "  Key Bits:       ${KEY_BITS}"
  fi
  echo -e "  Key Name:       ${KEY_NAME}"
  if [[ -n "$ENVIRONMENT" ]]; then
    echo -e "  Environment:    ${ENVIRONMENT}"
  fi
  if [[ -n "$INSTANCE_ID" ]]; then
    echo -e "  Instance ID:    ${INSTANCE_ID}"
  fi
  echo -e "  Secret Name:    ${SECRET_NAME}"
  echo -e "  AWS Region:     ${REGION}"
  echo -e "  AWS Profile:    ${PROFILE}"
  echo -e "  Output Dir:     ${OUTPUT_DIR}"
}

# Function validate_aws_credentials now imported from certificate-utils.sh

# Function to check if secret already exists
function check_existing_secret {
  echo -e "${BLUE}Checking if secret ${SECRET_NAME} already exists...${RESET}"
  
  if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region "$REGION" --profile "$PROFILE" &> /dev/null; then
    if [[ "$FORCE" == "true" ]]; then
      echo -e "${YELLOW}Secret ${SECRET_NAME} already exists. Will overwrite.${RESET}"
    else
      echo -e "${RED}Error: Secret ${SECRET_NAME} already exists. Use -f or --force to overwrite.${RESET}"
      exit 1
    fi
  else
    echo -e "${GREEN}✓ Secret name is available${RESET}"
  fi
}

# Function to generate SSH key
function generate_ssh_key {
  echo -e "${BLUE}Generating SSH key...${RESET}"
  
  # Create output directory
  mkdir -p "$OUTPUT_DIR"
  
  # Set file paths
  local KEY_FILE="${OUTPUT_DIR}/${KEY_NAME}"
  local KEY_FILE_PUB="${KEY_FILE}.pub"
  
  # Check if files already exist
  if [[ -f "$KEY_FILE" || -f "$KEY_FILE_PUB" ]]; then
    if [[ "$FORCE" == "true" ]]; then
      echo -e "${YELLOW}Key files already exist. Overwriting.${RESET}"
      rm -f "$KEY_FILE" "$KEY_FILE_PUB"
    else
      echo -e "${RED}Error: Key files already exist. Use -f or --force to overwrite.${RESET}"
      exit 1
    fi
  fi
  
  # Generate key
  if [[ "$KEY_TYPE" == "rsa" ]]; then
    ssh-keygen -t rsa -b "$KEY_BITS" -f "$KEY_FILE" -N "" -C "Generated by script for ${SECRET_NAME}"
  else
    ssh-keygen -t ed25519 -f "$KEY_FILE" -N "" -C "Generated by script for ${SECRET_NAME}"
  fi
  
  # Verify key files were created
  if [[ ! -f "$KEY_FILE" || ! -f "$KEY_FILE_PUB" ]]; then
    echo -e "${RED}Error: Failed to generate SSH key files.${RESET}"
    exit 1
  fi
  
  # Set secure permissions
  chmod 600 "$KEY_FILE"
  chmod 644 "$KEY_FILE_PUB"
  
  echo -e "${GREEN}✓ SSH key generated successfully${RESET}"
  echo -e "  Private key: ${KEY_FILE}"
  echo -e "  Public key:  ${KEY_FILE_PUB}"
}

# Function to create AWS secret
function create_aws_secret {
  echo -e "${BLUE}Creating AWS Secrets Manager secret...${RESET}"
  
  # Set file paths
  local KEY_FILE="${OUTPUT_DIR}/${KEY_NAME}"
  local KEY_FILE_PUB="${KEY_FILE}.pub"
  
  # Read key files
  local PRIVATE_KEY=$(cat "$KEY_FILE")
  local PUBLIC_KEY=$(cat "$KEY_FILE_PUB")
  
  # Prepare secret data based on type (instance or environment)
  local SECRET_DATA=""
  
  if [[ -n "$INSTANCE_ID" ]]; then
    # Instance-specific key format
    SECRET_DATA=$(jq -n \
      --arg private_key "$PRIVATE_KEY" \
      --arg public_key "$PUBLIC_KEY" \
      --arg key_name "$KEY_NAME" \
      --arg instance_id "$INSTANCE_ID" \
      --arg env "${ENVIRONMENT:-unknown}" \
      --arg created_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
      '{
        "private_key": $private_key,
        "public_key": $public_key,
        "key_name": $key_name,
        "instance_id": $instance_id,
        "environment": $env,
        "created_at": $created_at,
        "key_type": "instance-specific"
      }')
  else
    # Environment-wide key format
    SECRET_DATA=$(jq -n \
      --arg private_key "$PRIVATE_KEY" \
      --arg public_key "$PUBLIC_KEY" \
      --arg key_name "$KEY_NAME" \
      --arg env "$ENVIRONMENT" \
      --arg created_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
      '{
        "private_key": $private_key,
        "public_key": $public_key,
        "key_name": $key_name,
        "environment": $env,
        "created_at": $created_at,
        "key_type": "environment-wide"
      }')
  fi
  
  # Create or update the secret
  if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region "$REGION" --profile "$PROFILE" &> /dev/null; then
    # Secret exists, update it
    aws secretsmanager update-secret \
      --secret-id "$SECRET_NAME" \
      --secret-string "$SECRET_DATA" \
      --region "$REGION" \
      --profile "$PROFILE"
    echo -e "${GREEN}✓ Updated existing secret ${SECRET_NAME}${RESET}"
  else
    # Create new secret
    local TAGS="Key=Name,Value=${KEY_NAME} Key=Environment,Value=${ENVIRONMENT:-instance-specific} Key=ManagedBy,Value=generate-ssh-key-script"
    if [[ -n "$INSTANCE_ID" ]]; then
      TAGS="${TAGS} Key=InstanceId,Value=${INSTANCE_ID}"
    fi
    
    aws secretsmanager create-secret \
      --name "$SECRET_NAME" \
      --description "SSH key for ${KEY_NAME} (${INSTANCE_ID:-${ENVIRONMENT}})" \
      --secret-string "$SECRET_DATA" \
      --region "$REGION" \
      --profile "$PROFILE" \
      --tags ${TAGS}
    echo -e "${GREEN}✓ Created new secret ${SECRET_NAME}${RESET}"
  fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  key="$1"

  case $key in
    -t|--type)
      KEY_TYPE="$2"
      shift 2
      ;;
    -b|--bits)
      KEY_BITS="$2"
      shift 2
      ;;
    -n|--name)
      KEY_NAME="$2"
      shift 2
      ;;
    -e|--env)
      ENVIRONMENT="$2"
      shift 2
      ;;
    -i|--instance)
      INSTANCE_ID="$2"
      shift 2
      ;;
    -s|--secret)
      SECRET_NAME="$2"
      shift 2
      ;;
    -r|--region)
      REGION="$2"
      shift 2
      ;;
    -p|--profile)
      PROFILE="$2"
      shift 2
      ;;
    -o|--output)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    -f|--force)
      FORCE=true
      shift
      ;;
    -h|--help)
      show_usage
      ;;
    *)
      echo -e "${RED}Unknown option: $1${RESET}"
      show_usage
      ;;
  esac
done

# Main execution
check_requirements
validate_inputs
validate_aws_credentials
check_existing_secret
generate_ssh_key
create_aws_secret

echo
echo -e "${BOLD}${GREEN}SSH key generation completed successfully!${RESET}"
echo -e "${BOLD}Key details:${RESET}"
echo -e "  Type:        ${KEY_TYPE}"
if [[ "$KEY_TYPE" == "rsa" ]]; then
  echo -e "  Size:        ${KEY_BITS} bits"
fi
echo -e "  Name:        ${KEY_NAME}"
if [[ -n "$ENVIRONMENT" ]]; then
  echo -e "  Environment: ${ENVIRONMENT}"
fi
if [[ -n "$INSTANCE_ID" ]]; then
  echo -e "  Instance ID: ${INSTANCE_ID}"
fi
echo -e "  Private key: ${OUTPUT_DIR}/${KEY_NAME}"
echo -e "  Public key:  ${OUTPUT_DIR}/${KEY_NAME}.pub"
echo -e "  AWS Secret:  ${SECRET_NAME}"
echo -e "  Region:      ${REGION}"

echo
echo -e "${BOLD}To use this key with EC2:${RESET}"
echo -e "  1. Import to EC2: aws ec2 import-key-pair --key-name \"${KEY_NAME}\" --public-key-material fileb://${OUTPUT_DIR}/${KEY_NAME}.pub --region ${REGION} --profile ${PROFILE}"
echo -e "  2. Access instance with: ssh -i ${OUTPUT_DIR}/${KEY_NAME} ec2-user@your-instance-ip"

echo
echo -e "${BOLD}${YELLOW}SECURITY WARNING:${RESET}"
echo -e "${YELLOW}1. The private key is sensitive. Keep it secure or delete it once stored in Secrets Manager.${RESET}"
echo -e "${YELLOW}2. To retrieve this key later, use:${RESET}"
echo -e "   ./export-ssh-key.sh -s ${SECRET_NAME} -r ${REGION} -p ${PROFILE} -o ~/.ssh/${KEY_NAME}${RESET}"
echo -e ""

exit 0