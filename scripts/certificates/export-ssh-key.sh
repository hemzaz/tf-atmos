#!/usr/bin/env bash
set -e

# Script to pull SSH key from AWS Secrets Manager
# This script will download an SSH key from AWS Secrets Manager and save it locally

# Display usage information
usage() {
  echo "Usage: $0 [OPTIONS]"
  echo
  echo "Options:"
  echo "  -r, --region         AWS region (default: us-west-2)"
  echo "  -p, --profile        AWS profile (default: default)"
  echo "  -s, --secret-id      Secret ID/name in AWS Secrets Manager (required)"
  echo "  -i, --instance-id    EC2 instance ID (optional, needed for instance-specific keys)"
  echo "  -o, --output-file    Output file path (default: ./id_rsa)"
  echo "  -f, --force          Force overwrite if output file exists"
  echo "  -h, --help           Display this help message"
  echo
  echo "Example:"
  echo "  $0 -r us-east-1 -p myprofile -s dev/ec2/ssh-keys -o ~/.ssh/my_key"
  echo "  $0 -s dev/ec2/ssh-keys -i i-01234567890abcdef -o ~/.ssh/instance_key"
  exit 1
}

# Parse command line arguments
REGION="us-west-2"
PROFILE="default"
SECRET_ID=""
INSTANCE_ID=""
OUTPUT_FILE="./id_rsa"
FORCE=false

while [[ $# -gt 0 ]]; do
  case $1 in
    -r|--region)
      REGION="$2"
      shift 2
      ;;
    -p|--profile)
      PROFILE="$2"
      shift 2
      ;;
    -s|--secret-id)
      SECRET_ID="$2"
      shift 2
      ;;
    -i|--instance-id)
      INSTANCE_ID="$2"
      shift 2
      ;;
    -o|--output-file)
      OUTPUT_FILE="$2"
      shift 2
      ;;
    -f|--force)
      FORCE=true
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Error: Unknown option $1"
      usage
      ;;
  esac
done

# Validate required parameters
if [[ -z "$SECRET_ID" ]]; then
  echo "Error: Secret ID is required"
  usage
fi

# Check if output file exists and handle accordingly
if [[ -f "$OUTPUT_FILE" && "$FORCE" != "true" ]]; then
  echo "Error: Output file '$OUTPUT_FILE' already exists. Use -f to force overwrite."
  exit 1
fi

# Create directory for output file if it doesn't exist
OUTPUT_DIR=$(dirname "$OUTPUT_FILE")
mkdir -p "$OUTPUT_DIR"

# Get the secret from AWS Secrets Manager
echo "Retrieving SSH key from AWS Secrets Manager..."
if [[ -n "$INSTANCE_ID" ]]; then
  # For instance-specific keys
  SECRET_VALUE=$(aws secretsmanager get-secret-value \
    --region "$REGION" \
    --profile "$PROFILE" \
    --secret-id "$SECRET_ID" \
    --query "SecretString" \
    --output text)
  
  # Extract the private key for the specific instance
  PRIVATE_KEY=$(echo "$SECRET_VALUE" | jq -r --arg instance "$INSTANCE_ID" '.[$instance].private_key // empty')
  
  if [[ -z "$PRIVATE_KEY" ]]; then
    echo "Error: No key found for instance ID $INSTANCE_ID in secret $SECRET_ID"
    exit 1
  fi
else
  # For environment-wide keys
  SECRET_VALUE=$(aws secretsmanager get-secret-value \
    --region "$REGION" \
    --profile "$PROFILE" \
    --secret-id "$SECRET_ID" \
    --query "SecretString" \
    --output text)
  
  # For environment-wide keys, the secret should contain the private key directly
  # Try to parse as JSON first (new format)
  if echo "$SECRET_VALUE" | jq -e . >/dev/null 2>&1; then
    PRIVATE_KEY=$(echo "$SECRET_VALUE" | jq -r '.private_key // empty')
    
    # If not found, check for legacy format where the entire value is the key
    if [[ -z "$PRIVATE_KEY" ]]; then
      PRIVATE_KEY="$SECRET_VALUE"
    fi
  else
    # If not valid JSON, assume the entire value is the key (legacy format)
    PRIVATE_KEY="$SECRET_VALUE"
  fi
fi

# Save the private key to the output file
echo "$PRIVATE_KEY" > "$OUTPUT_FILE"
chmod 600 "$OUTPUT_FILE"

echo "Successfully saved SSH key to $OUTPUT_FILE"
echo "Remember to set the correct permissions: chmod 600 $OUTPUT_FILE"