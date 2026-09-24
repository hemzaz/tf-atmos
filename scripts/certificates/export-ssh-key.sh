#!/usr/bin/env bash
set -e

# Script to pull SSH key from AWS Secrets Manager
# This script will download an SSH key from AWS Secrets Manager and save it locally

# Display usage information
usage() {
  echo "Usage: $0 [OPTIONS]"
  echo
  echo "Options:"
  echo "  -r, --region         AWS region (default: \$AWS_REGION, then \$AWS_DEFAULT_REGION, then the AWS CLI config)"
  echo "  -p, --profile        AWS profile (default: the AWS CLI's own resolution, e.g. \$AWS_PROFILE)"
  echo "  -s, --secret-id      Secret ID/name in AWS Secrets Manager (required)"
  echo "  -i, --instance-id    EC2 instance ID (optional, needed for instance-specific keys)"
  echo "  -o, --output-file    Output file path (default: ./id_rsa)"
  echo "  -f, --force          Replace the output file if it exists (never done silently)"
  echo "  -h, --help           Display this help message"
  echo
  echo "Example:"
  echo "  $0 -r eu-west-2 -p myprofile -s ssh-key/testenv-01/bastion -o ~/.ssh/testenv-01-bastion"
  echo "  $0 -s ssh-key/testenv-01/bastion -i i-01234567890abcdef -o ~/.ssh/instance_key"
  exit 1
}

# Parse command line arguments. Region and profile default to the ambient AWS
# configuration: each is passed to the AWS CLI only when set.
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
PROFILE=""
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

# Never overwrite silently: anything at the output path needs -f
if [[ -e "$OUTPUT_FILE" && "$FORCE" != "true" ]]; then
  echo "Error: Output file '$OUTPUT_FILE' already exists. Use -f to force overwrite."
  exit 1
fi

# Create directory for output file if it doesn't exist
OUTPUT_DIR=$(dirname "$OUTPUT_FILE")
mkdir -p "$OUTPUT_DIR"

# Get the secret from AWS Secrets Manager
echo "Retrieving SSH key from AWS Secrets Manager..."
AWS_ARGS=()
if [[ -n "$REGION" ]]; then
  AWS_ARGS+=(--region "$REGION")
fi
if [[ -n "$PROFILE" ]]; then
  AWS_ARGS+=(--profile "$PROFILE")
fi
SECRET_VALUE=$(aws secretsmanager get-secret-value \
  "${AWS_ARGS[@]}" \
  --secret-id "$SECRET_ID" \
  --query "SecretString" \
  --output text)

# The ec2 component writes one JSON secret per instance
# (ssh-key/<Environment>/<name>) holding private_key_openssh, private_key_pem,
# public_key_openssh, key_name and instance_id. Prefer the OpenSSH form: for
# ED25519 keys private_key_pem is PKCS#8, which OpenSSH rejects ("invalid
# format"). private_key is the legacy field name.
KEY_FILTER='.private_key_openssh // .private_key_pem // .private_key // empty'
if echo "$SECRET_VALUE" | jq -e 'type == "object"' >/dev/null 2>&1; then
  if [[ -n "$INSTANCE_ID" ]]; then
    SECRET_INSTANCE=$(echo "$SECRET_VALUE" | jq -r '.instance_id // empty')
    if [[ -n "$SECRET_INSTANCE" ]]; then
      if [[ "$SECRET_INSTANCE" != "$INSTANCE_ID" ]]; then
        echo "Error: secret $SECRET_ID belongs to instance $SECRET_INSTANCE, not $INSTANCE_ID"
        exit 1
      fi
      PRIVATE_KEY=$(echo "$SECRET_VALUE" | jq -r "$KEY_FILTER")
    else
      # Legacy layout: one secret with a map keyed by instance ID
      PRIVATE_KEY=$(echo "$SECRET_VALUE" | jq -r --arg instance "$INSTANCE_ID" ".[\$instance] | $KEY_FILTER")
    fi
  else
    PRIVATE_KEY=$(echo "$SECRET_VALUE" | jq -r "$KEY_FILTER")
  fi
else
  # Not JSON: the whole value is the key (legacy format)
  PRIVATE_KEY="$SECRET_VALUE"
fi

if [[ -z "$PRIVATE_KEY" ]]; then
  echo "Error: no private key found in secret $SECRET_ID${INSTANCE_ID:+ for instance $INSTANCE_ID}"
  exit 1
fi

# Save the private key: created under umask 077, so it is never readable by
# others, not even for a moment. With -f the old file is removed first, so a
# looser mode on it does not carry over.
if [[ -e "$OUTPUT_FILE" ]]; then
  rm -f "$OUTPUT_FILE"
fi
(umask 077; printf '%s\n' "$PRIVATE_KEY" > "$OUTPUT_FILE")

echo "Successfully saved SSH key to $OUTPUT_FILE (mode 600)"