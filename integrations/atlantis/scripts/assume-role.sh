#!/bin/bash
set -eo pipefail

# Script to handle AWS cross-account role assumption
# Usage: assume-role.sh ACCOUNT_ID ROLE_NAME SESSION_NAME

# Check if all required arguments are provided
if [ "$#" -lt 3 ]; then
    echo "Usage: assume-role.sh ACCOUNT_ID ROLE_NAME SESSION_NAME [DURATION_SECONDS]"
    echo "Example: assume-role.sh 123456789012 OrganizationAccountAccessRole atlantis-session"
    exit 1
fi

ACCOUNT_ID="$1"
ROLE_NAME="$2"
SESSION_NAME="$3"
DURATION="${4:-3600}"  # Default to 1 hour

# Check for required tools
if ! command -v aws >/dev/null 2>&1; then
    echo "Error: AWS CLI is not installed. Please install it first."
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is not installed. This tool is required for JSON parsing."
    echo "Please install jq: https://stedolan.github.io/jq/download/"
    exit 1
fi

# Validate input parameters
if [[ ! "$ACCOUNT_ID" =~ ^[0-9]{12}$ ]]; then
    echo "Error: Account ID must be a 12-digit number"
    exit 1
fi

if [[ ! "$SESSION_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "Error: Session name can only contain alphanumeric characters, hyphens, and underscores"
    exit 1
fi

if [[ ! "$DURATION" =~ ^[0-9]+$ ]] || [ "$DURATION" -lt 900 ] || [ "$DURATION" -gt 43200 ]; then
    echo "Error: Duration must be a number between 900 and 43200 seconds"
    exit 1
fi

# Role ARN to assume
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"

echo "Assuming role: ${ROLE_ARN}"
echo "Session name: ${SESSION_NAME}"
echo "Duration: ${DURATION} seconds"

# Assume the role and capture the output
TEMP_CREDS=$(aws sts assume-role \
    --role-arn "${ROLE_ARN}" \
    --role-session-name "${SESSION_NAME}" \
    --duration-seconds "${DURATION}" \
    --output json)

# Check if the command was successful
if [ $? -ne 0 ]; then
    echo "Error: Failed to assume role ${ROLE_ARN}"
    exit 1
fi

# Extract credentials from the response
export AWS_ACCESS_KEY_ID=$(echo "${TEMP_CREDS}" | jq -r .Credentials.AccessKeyId)
export AWS_SECRET_ACCESS_KEY=$(echo "${TEMP_CREDS}" | jq -r .Credentials.SecretAccessKey)
export AWS_SESSION_TOKEN=$(echo "${TEMP_CREDS}" | jq -r .Credentials.SessionToken)

# Verify credentials work
echo "Verifying credentials..."
aws sts get-caller-identity

if [ $? -eq 0 ]; then
    echo "Successfully assumed role ${ROLE_ARN}"
    echo "Credentials will expire at $(echo "${TEMP_CREDS}" | jq -r .Credentials.Expiration)"
    
    # Output variable exports for sourcing
    echo ""
    echo "To use these credentials in your shell, run:"
    echo "export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}"
    echo "export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}"
    echo "export AWS_SESSION_TOKEN=${AWS_SESSION_TOKEN}"
    
    # Create credentials file for future use
    mkdir -p /atlantis/.aws
    cat > /atlantis/.aws/credentials.${SESSION_NAME} <<EOF
[default]
aws_access_key_id = ${AWS_ACCESS_KEY_ID}
aws_secret_access_key = ${AWS_SECRET_ACCESS_KEY}
aws_session_token = ${AWS_SESSION_TOKEN}
EOF
    
    echo ""
    echo "Credentials file created at /atlantis/.aws/credentials.${SESSION_NAME}"
    
    exit 0
else
    echo "Error: Failed to verify credentials"
    exit 1
fi