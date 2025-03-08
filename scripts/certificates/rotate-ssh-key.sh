#!/usr/bin/env bash
set -e

# SSH Key Rotation Script
# This script safely rotates SSH keys for EC2 instances with proper validation

# Import common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/certificate-utils.sh"

# Default values
SECRET_NAME=""
INSTANCE_ID=""
ENVIRONMENT=""
REGION=""
PROFILE="default"
KEY_NAME=""
KEY_TYPE="rsa"
KEY_BITS=4096
FORCE=false
VERIFY=true
BACKUP_DIR="./key-backups"
OUTPUT_DIR="./generated-keys"
USE_SSM=true
USER="ec2-user"
HOST=""

# Display usage information
function show_usage {
  echo -e "${BOLD}SSH Key Rotation Script${RESET}"
  echo -e "Safely rotates SSH keys for EC2 instances with secure validation"
  echo
  echo -e "${BOLD}Usage:${RESET}"
  echo -e "  $0 [options]"
  echo
  echo -e "${BOLD}Options:${RESET}"
  echo -e "  -s, --secret SECRET   AWS Secret Manager secret name (required)"
  echo -e "  -i, --instance INST   Instance ID (for instance-specific keys)"
  echo -e "  -e, --env ENV         Environment name (for environment-wide keys)"
  echo -e "  -h, --host HOST       Instance hostname/IP (if not using instance ID)"
  echo -e "  -n, --name NAME       Key name (default: derived from secret/instance)"
  echo -e "  -t, --type TYPE       Key type for new key (rsa or ed25519, default: rsa)"
  echo -e "  -b, --bits BITS       Key size in bits for RSA keys (default: 4096)"
  echo -e "  -r, --region REGION   AWS region (default: current AWS CLI region)"
  echo -e "  -p, --profile PROFILE AWS profile (default: default)"
  echo -e "  -u, --user USER       SSH user (default: ec2-user)"
  echo -e "      --no-ssm          Don't use SSM for connection (use direct SSH)"
  echo -e "      --no-verify       Skip connectivity verification (not recommended)"
  echo -e "  -f, --force           Force rotation even if validation fails"
  echo -e "      --help            Show this help"
  echo
  echo -e "${BOLD}Examples:${RESET}"
  echo -e "  # Rotate key for a specific instance"
  echo -e "  $0 -s ssh-key/instance/i-0123456789abcdef0/bastion -i i-0123456789abcdef0"
  echo
  echo -e "  # Rotate environment-wide key"
  echo -e "  $0 -s ssh-key/prod/global-keys/app-servers -e prod -h 10.0.1.5"
  echo
  exit 1
}

# Function to check SSH-specific requirements
function check_ssh_requirements {
  local MISSING_REQS=false
  
  if ! command -v ssh &> /dev/null; then
    echo -e "${RED}✘ ssh is not installed. Please install OpenSSH.${RESET}"
    MISSING_REQS=true
  else
    echo -e "${GREEN}✓ ssh is installed${RESET}"
  fi
  
  if [[ "$USE_SSM" == "true" ]]; then
    if ! command -v session-manager-plugin &> /dev/null; then
      echo -e "${YELLOW}⚠ AWS Session Manager Plugin is not installed.${RESET}"
      echo -e "${YELLOW}⚠ Will attempt to use direct SSH instead.${RESET}"
      USE_SSM=false
    else
      echo -e "${GREEN}✓ AWS Session Manager Plugin is installed${RESET}"
    fi
  fi
  
  if [[ "$MISSING_REQS" == "true" ]]; then
    echo -e "${RED}Please install missing requirements and try again.${RESET}"
    exit 1
  fi
}

# Function to validate inputs
function validate_inputs {
  # Secret name is required
  if [[ -z "$SECRET_NAME" ]]; then
    echo -e "${RED}Error: Secret name is required. Use -s or --secret.${RESET}"
    show_usage
  fi
  
  # Either instance ID, environment, or host is required
  if [[ -z "$INSTANCE_ID" && -z "$ENVIRONMENT" && -z "$HOST" ]]; then
    echo -e "${RED}Error: Either instance ID, environment, or host is required.${RESET}"
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
  
  # If using host, it's required
  if [[ -z "$INSTANCE_ID" && -z "$HOST" ]]; then
    echo -e "${RED}Error: When using environment-wide keys, a host is required for validation.${RESET}"
    show_usage
  fi
  
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
  
  # If region not provided, use AWS CLI default
  if [[ -z "$REGION" ]]; then
    REGION=$(aws configure get region --profile "$PROFILE")
    if [[ -z "$REGION" ]]; then
      echo -e "${RED}Error: AWS region not specified and not found in AWS CLI config.${RESET}"
      exit 1
    fi
  fi
  
  # Extract key name from secret path if not specified
  if [[ -z "$KEY_NAME" ]]; then
    KEY_NAME=$(basename "$SECRET_NAME")
  fi
  
  echo -e "${BLUE}Using parameters:${RESET}"
  echo -e "  Secret:          ${SECRET_NAME}"
  if [[ -n "$INSTANCE_ID" ]]; then
    echo -e "  Instance ID:     ${INSTANCE_ID}"
  fi
  if [[ -n "$ENVIRONMENT" ]]; then
    echo -e "  Environment:     ${ENVIRONMENT}"
  fi
  if [[ -n "$HOST" ]]; then
    echo -e "  Host:            ${HOST}"
  fi
  echo -e "  Key Name:        ${KEY_NAME}"
  echo -e "  Key Type:        ${KEY_TYPE}"
  if [[ "$KEY_TYPE" == "rsa" ]]; then
    echo -e "  Key Bits:        ${KEY_BITS}"
  fi
  echo -e "  AWS Region:      ${REGION}"
  echo -e "  AWS Profile:     ${PROFILE}"
  echo -e "  SSH User:        ${USER}"
  echo -e "  Using SSM:       ${USE_SSM}"
  echo -e "  Verify:          ${VERIFY}"
}

# Function validate_aws_credentials now imported from certificate-utils.sh

# Function to get the existing key
function get_existing_key {
  echo -e "${BLUE}Retrieving existing key from Secrets Manager...${RESET}"
  
  # Create backup directory
  mkdir -p "$BACKUP_DIR"
  
  # Set backup key file path
  local BACKUP_KEY_FILE="${BACKUP_DIR}/${KEY_NAME}-backup"
  
  # Get the secret
  if ! SECRET_VALUE=$(aws secretsmanager get-secret-value \
    --secret-id "$SECRET_NAME" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query 'SecretString' \
    --output text); then
    echo -e "${RED}Error: Failed to retrieve secret. Check secret name and permissions.${RESET}"
    exit 1
  fi
  
  # Extract private key and public key
  if ! PRIVATE_KEY=$(echo "$SECRET_VALUE" | jq -r '.private_key // empty'); then
    echo -e "${RED}Error: Failed to parse secret JSON. Invalid format.${RESET}"
    exit 1
  fi
  
  # If empty or not found, try alternate formats
  if [[ -z "$PRIVATE_KEY" ]]; then
    # Try alternative field names
    PRIVATE_KEY=$(echo "$SECRET_VALUE" | jq -r '.private_key_pem // .["private_key"] // empty')
    
    # If still empty, check if the entire secret is the key
    if [[ -z "$PRIVATE_KEY" ]]; then
      # Check if the content looks like a private key
      if [[ "$SECRET_VALUE" == *"BEGIN"*"PRIVATE KEY"* ]]; then
        PRIVATE_KEY="$SECRET_VALUE"
      else
        echo -e "${RED}Error: Could not find private key in secret. Check format.${RESET}"
        exit 1
      fi
    fi
  fi
  
  # Get public key if available
  PUBLIC_KEY=$(echo "$SECRET_VALUE" | jq -r '.public_key // .public_key_openssh // empty')
  
  # Save private key to backup file
  echo "$PRIVATE_KEY" > "$BACKUP_KEY_FILE"
  chmod 600 "$BACKUP_KEY_FILE"
  
  # If we have a public key, save it too
  if [[ -n "$PUBLIC_KEY" ]]; then
    echo "$PUBLIC_KEY" > "${BACKUP_KEY_FILE}.pub"
    chmod 644 "${BACKUP_KEY_FILE}.pub"
  else
    # Generate public key from private key
    echo -e "${YELLOW}Public key not found in secret. Generating from private key...${RESET}"
    ssh-keygen -y -f "$BACKUP_KEY_FILE" > "${BACKUP_KEY_FILE}.pub"
    chmod 644 "${BACKUP_KEY_FILE}.pub"
  fi
  
  echo -e "${GREEN}✓ Existing key retrieved and backed up${RESET}"
  echo -e "  Backup private key: ${BACKUP_KEY_FILE}"
  echo -e "  Backup public key:  ${BACKUP_KEY_FILE}.pub"
  
  # Check if we have instance ID or need to extract it
  if [[ -z "$INSTANCE_ID" && -z "$HOST" ]]; then
    # Try to get instance ID from secret
    EXTRACTED_INSTANCE_ID=$(echo "$SECRET_VALUE" | jq -r '.instance_id // empty')
    if [[ -n "$EXTRACTED_INSTANCE_ID" ]]; then
      INSTANCE_ID="$EXTRACTED_INSTANCE_ID"
      echo -e "${GREEN}✓ Found instance ID in secret: ${INSTANCE_ID}${RESET}"
    else
      # Check for instance details
      INSTANCE_DETAILS=$(echo "$SECRET_VALUE" | jq -r '.instance_details // empty')
      if [[ -n "$INSTANCE_DETAILS" ]]; then
        # Take the first instance from the details
        EXTRACTED_INSTANCE_ID=$(echo "$SECRET_VALUE" | jq -r '.instance_details | keys | .[0]')
        if [[ -n "$EXTRACTED_INSTANCE_ID" ]]; then
          INSTANCE_ID="$EXTRACTED_INSTANCE_ID"
          echo -e "${GREEN}✓ Found instance ID in instance details: ${INSTANCE_ID}${RESET}"
        fi
      fi
    fi
    
    # If still no instance ID and no host, we need one to proceed
    if [[ -z "$INSTANCE_ID" && -z "$HOST" ]]; then
      echo -e "${RED}Error: Could not determine instance ID from secret.${RESET}"
      echo -e "${RED}Please provide instance ID (-i) or host (-h) for validation.${RESET}"
      exit 1
    fi
  fi
}

# Function to verify connectivity with existing key
function verify_connectivity {
  if [[ "$VERIFY" != "true" ]]; then
    echo -e "${YELLOW}Skipping connectivity verification as requested.${RESET}"
    return
  fi
  
  echo -e "${BLUE}Verifying connectivity with existing key...${RESET}"
  
  local BACKUP_KEY_FILE="${BACKUP_DIR}/${KEY_NAME}-backup"
  local SSH_OPTIONS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes"
  
  # Determine the host to connect to
  if [[ -z "$HOST" && -n "$INSTANCE_ID" ]]; then
    if [[ "$USE_SSM" == "true" ]]; then
      # Use SSM to verify connectivity
      echo -e "${BLUE}Using SSM Session Manager to verify connectivity...${RESET}"
      if ! aws ssm start-session \
        --target "$INSTANCE_ID" \
        --document-name "AWS-StartInteractiveCommand" \
        --parameters command="echo Connected to $(hostname) successfully" \
        --region "$REGION" \
        --profile "$PROFILE"; then
        echo -e "${RED}✘ Failed to connect using SSM. Check instance ID and permissions.${RESET}"
        if [[ "$FORCE" != "true" ]]; then
          echo -e "${RED}Use --force to proceed anyway (not recommended).${RESET}"
          exit 1
        else
          echo -e "${YELLOW}Proceeding despite connection failure due to --force option.${RESET}"
        fi
      else
        echo -e "${GREEN}✓ SSM connection successful${RESET}"
      fi
    else
      # Get instance public IP
      echo -e "${BLUE}Retrieving instance IP address...${RESET}"
      HOST=$(aws ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --query "Reservations[0].Instances[0].PublicIpAddress" \
        --region "$REGION" \
        --profile "$PROFILE" \
        --output text)
      
      if [[ -z "$HOST" || "$HOST" == "None" ]]; then
        # Try private IP if public not available
        HOST=$(aws ec2 describe-instances \
          --instance-ids "$INSTANCE_ID" \
          --query "Reservations[0].Instances[0].PrivateIpAddress" \
          --region "$REGION" \
          --profile "$PROFILE" \
          --output text)
        
        if [[ -z "$HOST" || "$HOST" == "None" ]]; then
          echo -e "${RED}✘ Could not determine instance IP address.${RESET}"
          if [[ "$FORCE" != "true" ]]; then
            echo -e "${RED}Use --force to proceed anyway or provide host with -h option.${RESET}"
            exit 1
          else
            echo -e "${YELLOW}Proceeding despite IP resolution failure due to --force option.${RESET}"
            return
          fi
        fi
      fi
      
      echo -e "${GREEN}✓ Using host: ${HOST}${RESET}"
    fi
  fi
  
  # If we have a host, try SSH connection
  if [[ -n "$HOST" ]]; then
    echo -e "${BLUE}Verifying SSH connectivity to ${HOST}...${RESET}"
    if ! ssh $SSH_OPTIONS -i "$BACKUP_KEY_FILE" "${USER}@${HOST}" "echo 'Connection successful'" &>/dev/null; then
      echo -e "${RED}✘ Failed to connect via SSH using existing key.${RESET}"
      if [[ "$FORCE" != "true" ]]; then
        echo -e "${RED}Use --force to proceed anyway (not recommended).${RESET}"
        exit 1
      else
        echo -e "${YELLOW}Proceeding despite connection failure due to --force option.${RESET}"
      fi
    else
      echo -e "${GREEN}✓ SSH connection successful${RESET}"
    fi
  fi
}

# Function to generate new key
function generate_new_key {
  echo -e "${BLUE}Generating new SSH key...${RESET}"
  
  # Create output directory
  mkdir -p "$OUTPUT_DIR"
  
  # Set file paths
  local KEY_FILE="${OUTPUT_DIR}/${KEY_NAME}"
  local KEY_FILE_PUB="${KEY_FILE}.pub"
  
  # Check if files already exist
  if [[ -f "$KEY_FILE" || -f "$KEY_FILE_PUB" ]]; then
    echo -e "${YELLOW}Key files already exist. Overwriting.${RESET}"
    rm -f "$KEY_FILE" "$KEY_FILE_PUB"
  fi
  
  # Generate key
  if [[ "$KEY_TYPE" == "rsa" ]]; then
    ssh-keygen -t rsa -b "$KEY_BITS" -f "$KEY_FILE" -N "" -C "Rotated key for ${SECRET_NAME} $(date +%Y-%m-%d)"
  else
    ssh-keygen -t ed25519 -f "$KEY_FILE" -N "" -C "Rotated key for ${SECRET_NAME} $(date +%Y-%m-%d)"
  fi
  
  # Verify key files were created
  if [[ ! -f "$KEY_FILE" || ! -f "$KEY_FILE_PUB" ]]; then
    echo -e "${RED}Error: Failed to generate SSH key files.${RESET}"
    exit 1
  fi
  
  # Set secure permissions
  chmod 600 "$KEY_FILE"
  chmod 644 "$KEY_FILE_PUB"
  
  echo -e "${GREEN}✓ New SSH key generated successfully${RESET}"
  echo -e "  Private key: ${KEY_FILE}"
  echo -e "  Public key:  ${KEY_FILE_PUB}"
}

# Function to update authorized_keys on instance
function update_authorized_keys {
  if [[ -z "$HOST" && -z "$INSTANCE_ID" ]]; then
    echo -e "${YELLOW}No host or instance ID available for authorized_keys update.${RESET}"
    return
  fi
  
  echo -e "${BLUE}Updating authorized_keys on target...${RESET}"
  
  local BACKUP_KEY_FILE="${BACKUP_DIR}/${KEY_NAME}-backup"
  local NEW_KEY_FILE="${OUTPUT_DIR}/${KEY_NAME}"
  local NEW_KEY_PUB=$(cat "${NEW_KEY_FILE}.pub")
  local SSH_OPTIONS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes"
  
  # Use SSM if available and requested
  if [[ -n "$INSTANCE_ID" && "$USE_SSM" == "true" ]]; then
    echo -e "${BLUE}Using SSM Session Manager to update authorized_keys...${RESET}"
    
    # Create a temporary script to run on the instance that tests the key before fully deploying
    local TEMP_SCRIPT=$(mktemp)
    cat > "$TEMP_SCRIPT" << EOF
#!/bin/bash
set -e
SSH_DIR=~/.ssh
AUTH_KEYS=\$SSH_DIR/authorized_keys
AUTH_KEYS_TEMP=\$SSH_DIR/authorized_keys.new
mkdir -p \$SSH_DIR
chmod 700 \$SSH_DIR
touch \$AUTH_KEYS
chmod 600 \$AUTH_KEYS

# First, add the new key to a separate temporary authorized_keys file for validation
cp \$AUTH_KEYS \$AUTH_KEYS_TEMP
echo "$NEW_KEY_PUB" >> \$AUTH_KEYS_TEMP
sort -u \$AUTH_KEYS_TEMP -o \$AUTH_KEYS_TEMP
chmod 600 \$AUTH_KEYS_TEMP

# Create a test script that will be used to validate the key
cat > /tmp/validate_key.sh << 'TEST_EOF'
#!/bin/bash
echo "KEY_VALIDATION_SUCCESS"
TEST_EOF
chmod +x /tmp/validate_key.sh

# Create marker file to indicate test in progress
touch /tmp/ssh_key_test_in_progress

echo "Temporary authorized_keys file created for validation"
EOF
    
    # Execute the setup script via SSM using a more secure approach
    # First, create the parameters JSON file with proper escaping 
    PARAMS_FILE=$(mktemp)
    
    # Ensure cleanup of temp file
    trap 'rm -f "$PARAMS_FILE"' EXIT
    
    # Content is properly escaped using a heredoc to prevent injection
    # Use jq to create a valid JSON structure rather than string interpolation
    cat <<EOF > "$PARAMS_FILE"
{
  "commands": [
    "cat > /tmp/update_keys_setup.sh << 'EOFMARKER'",
    $(cat "$TEMP_SCRIPT" | jq -Rs .),
    "EOFMARKER",
    "chmod 700 /tmp/update_keys_setup.sh",
    "sudo -u $USER /tmp/update_keys_setup.sh",
    "rm -f /tmp/update_keys_setup.sh"
  ]
}
EOF
    
    # Execute the command with the file parameter rather than inline string
    if ! aws ssm send-command \
      --instance-ids "$INSTANCE_ID" \
      --document-name "AWS-RunShellScript" \
      --parameters file://"$PARAMS_FILE" \
      --region "$REGION" \
      --profile "$PROFILE" \
      --output text > /dev/null; then
      echo -e "${RED}✘ Failed to setup key validation via SSM.${RESET}"
      if [[ "$FORCE" != "true" ]]; then
        echo -e "${RED}Use --force to proceed anyway.${RESET}"
        exit 1
      else
        echo -e "${YELLOW}Proceeding despite setup failure due to --force option.${RESET}"
      fi
    else
      echo -e "${GREEN}✓ Key validation setup completed${RESET}"
      
      # Create the commit script that will be executed after validation
      local COMMIT_SCRIPT=$(mktemp)
      cat > "$COMMIT_SCRIPT" << EOF
#!/bin/bash
set -e
SSH_DIR=~/.ssh
AUTH_KEYS=\$SSH_DIR/authorized_keys
AUTH_KEYS_TEMP=\$SSH_DIR/authorized_keys.new

# Check if validation was successful
if [ -f /tmp/ssh_key_validation_success ]; then
  # Validation succeeded, commit the changes
  mv \$AUTH_KEYS_TEMP \$AUTH_KEYS
  chmod 600 \$AUTH_KEYS
  echo "New key successfully committed to authorized_keys"
else
  # Validation failed or didn't happen
  echo "Key validation failed or was not completed"
  rm -f \$AUTH_KEYS_TEMP
fi

# Clean up
rm -f /tmp/validate_key.sh
rm -f /tmp/ssh_key_test_in_progress
rm -f /tmp/ssh_key_validation_success
EOF
      
      # Now we need to try to connect with the new key to validate it works
      echo -e "${BLUE}Validating new key before committing...${RESET}"
      # Wait a moment for SSM to complete setup
      sleep 2
      
      # Check if we have a host to connect to for validation
      if [[ -n "$HOST" ]]; then
        # Try to connect with the new key to execute the validation script
        if ssh $SSH_OPTIONS -i "$NEW_KEY_FILE" "${USER}@${HOST}" "DISPLAY=:0 TERM=xterm-256color SSH_AUTH_SOCK= ~/.ssh/authorized_keys.new bash /tmp/validate_key.sh" | grep -q "KEY_VALIDATION_SUCCESS"; then
          echo -e "${GREEN}✓ New key validation successful${RESET}"
          
          # Mark validation as successful
          ssh $SSH_OPTIONS -i "$BACKUP_KEY_FILE" "${USER}@${HOST}" "touch /tmp/ssh_key_validation_success"
          
          # Execute the commit script
          if ! aws ssm send-command \
            --instance-ids "$INSTANCE_ID" \
            --document-name "AWS-RunShellScript" \
            --parameters "commands=[cat > /tmp/commit_keys.sh << 'EOFMARKER'
$(cat $COMMIT_SCRIPT)
EOFMARKER
chmod +x /tmp/commit_keys.sh
sudo -u $USER /tmp/commit_keys.sh
rm /tmp/commit_keys.sh]" \
            --region "$REGION" \
            --profile "$PROFILE" \
            --output text > /dev/null; then
            echo -e "${RED}✘ Failed to commit new key.${RESET}"
            exit 1
          else
            echo -e "${GREEN}✓ New key committed successfully${RESET}"
          fi
        else
          echo -e "${RED}✘ Failed to validate new key.${RESET}"
          if [[ "$FORCE" != "true" ]]; then
            echo -e "${RED}Use --force to proceed anyway.${RESET}"
            exit 1
          else
            echo -e "${YELLOW}Forcing key update despite validation failure...${RESET}"
            
            # Force direct update of authorized_keys
            if ! ssh $SSH_OPTIONS -i "$BACKUP_KEY_FILE" "${USER}@${HOST}" "echo '$NEW_KEY_PUB' >> ~/.ssh/authorized_keys && sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys"; then
              echo -e "${RED}✘ Failed to force update authorized_keys.${RESET}"
              exit 1
            else
              echo -e "${GREEN}✓ Forced key update completed${RESET}"
            fi
          fi
        fi
      else
        echo -e "${YELLOW}No host available for key validation. Proceeding with direct update...${RESET}"
        
        # Execute direct update via SSM
        if ! aws ssm send-command \
          --instance-ids "$INSTANCE_ID" \
          --document-name "AWS-RunShellScript" \
          --parameters "commands=[cat > /tmp/direct_update.sh << 'EOFMARKER'
#!/bin/bash
set -e
SSH_DIR=~/.ssh
AUTH_KEYS=\$SSH_DIR/authorized_keys
mkdir -p \$SSH_DIR
chmod 700 \$SSH_DIR
touch \$AUTH_KEYS
chmod 600 \$AUTH_KEYS
echo \"$NEW_KEY_PUB\" >> \$AUTH_KEYS
sort -u \$AUTH_KEYS -o \$AUTH_KEYS
echo \"Direct key update completed\"
EOFMARKER
chmod +x /tmp/direct_update.sh
sudo -u $USER /tmp/direct_update.sh
rm /tmp/direct_update.sh]" \
          --region "$REGION" \
          --profile "$PROFILE" \
          --output text > /dev/null; then
          echo -e "${RED}✘ Failed to update authorized_keys via SSM.${RESET}"
          if [[ "$FORCE" != "true" ]]; then
            echo -e "${RED}Use --force to proceed anyway.${RESET}"
            exit 1
          else
            echo -e "${YELLOW}Proceeding despite update failure due to --force option.${RESET}"
          fi
        else
          echo -e "${GREEN}✓ Authorized keys updated via SSM${RESET}"
        fi
      fi
    fi
    
    # Clean up temp files
    rm -f "$TEMP_SCRIPT" "$COMMIT_SCRIPT" 2>/dev/null || true
  elif [[ -n "$HOST" ]]; then
    # Use SSH with existing key to update authorized_keys
    echo -e "${BLUE}Using SSH to update authorized_keys on ${HOST}...${RESET}"
    
    # First create a temporary authorized_keys file with the new key for validation
    if ! ssh $SSH_OPTIONS -i "$BACKUP_KEY_FILE" "${USER}@${HOST}" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cp ~/.ssh/authorized_keys ~/.ssh/authorized_keys.new 2>/dev/null || touch ~/.ssh/authorized_keys.new && echo '$NEW_KEY_PUB' >> ~/.ssh/authorized_keys.new && chmod 600 ~/.ssh/authorized_keys.new"; then
      echo -e "${RED}✘ Failed to create temporary authorized_keys file.${RESET}"
      if [[ "$FORCE" != "true" ]]; then
        echo -e "${RED}Use --force to proceed anyway.${RESET}"
        exit 1
      else
        echo -e "${YELLOW}Proceeding with direct update due to --force option.${RESET}"
        if ! ssh $SSH_OPTIONS -i "$BACKUP_KEY_FILE" "${USER}@${HOST}" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$NEW_KEY_PUB' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys"; then
          echo -e "${RED}✘ Failed to update authorized_keys via SSH.${RESET}"
          exit 1
        else
          echo -e "${GREEN}✓ Authorized keys directly updated via SSH${RESET}"
          return
        fi
      fi
    fi
    
    # Now try to connect with the new key to validate it works
    echo -e "${BLUE}Validating new key before committing...${RESET}"
    if ssh $SSH_OPTIONS -i "$NEW_KEY_FILE" -o "AuthorizedKeysFile=.ssh/authorized_keys.new" "${USER}@${HOST}" "echo 'KEY_VALIDATION_SUCCESS'" | grep -q "KEY_VALIDATION_SUCCESS"; then
      echo -e "${GREEN}✓ New key validation successful${RESET}"
      
      # Commit the new authorized_keys file
      if ! ssh $SSH_OPTIONS -i "$BACKUP_KEY_FILE" "${USER}@${HOST}" "mv ~/.ssh/authorized_keys.new ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys"; then
        echo -e "${RED}✘ Failed to commit new authorized_keys file.${RESET}"
        exit 1
      else
        echo -e "${GREEN}✓ New key committed to authorized_keys${RESET}"
      fi
    else
      echo -e "${RED}✘ Failed to validate new key.${RESET}"
      if [[ "$FORCE" != "true" ]]; then
        echo -e "${RED}Use --force to proceed anyway.${RESET}"
        exit 1
      else
        echo -e "${YELLOW}Forcing key update despite validation failure...${RESET}"
        
        # Force direct update of authorized_keys
        if ! ssh $SSH_OPTIONS -i "$BACKUP_KEY_FILE" "${USER}@${HOST}" "mv ~/.ssh/authorized_keys.new ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"; then
          echo -e "${RED}✘ Failed to force update authorized_keys.${RESET}"
          exit 1
        else
          echo -e "${GREEN}✓ Forced key update completed${RESET}"
        fi
      fi
    fi
  else
    echo -e "${YELLOW}⚠ No method available to update authorized_keys automatically.${RESET}"
    echo -e "${YELLOW}⚠ You'll need to manually update the authorized_keys on the target instance.${RESET}"
    echo -e "${YELLOW}⚠ Add this line to ~/.ssh/authorized_keys:${RESET}"
    echo -e "${YELLOW}${NEW_KEY_PUB}${RESET}"
  fi
}

# Function to verify new key connectivity
function verify_new_key {
  if [[ "$VERIFY" != "true" || ( -z "$HOST" && -z "$INSTANCE_ID" ) ]]; then
    echo -e "${YELLOW}Skipping new key connectivity verification.${RESET}"
    return
  fi
  
  echo -e "${BLUE}Verifying connectivity with new key...${RESET}"
  
  local NEW_KEY_FILE="${OUTPUT_DIR}/${KEY_NAME}"
  local SSH_OPTIONS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes"
  
  # If we have a host, try direct SSH connection
  if [[ -n "$HOST" ]]; then
    echo -e "${BLUE}Verifying SSH connectivity to ${HOST} with new key...${RESET}"
    if ! ssh $SSH_OPTIONS -i "$NEW_KEY_FILE" "${USER}@${HOST}" "echo 'New key connection successful'" &>/dev/null; then
      echo -e "${RED}✘ Failed to connect via SSH using new key.${RESET}"
      if [[ "$FORCE" != "true" ]]; then
        echo -e "${RED}Key rotation may have failed. Use --force to proceed anyway.${RESET}"
        exit 1
      else
        echo -e "${YELLOW}Proceeding despite connection failure due to --force option.${RESET}"
      fi
    else
      echo -e "${GREEN}✓ SSH connection with new key successful${RESET}"
    fi
  elif [[ -n "$INSTANCE_ID" && "$USE_SSM" == "true" ]]; then
    # Using SSM doesn't verify the key itself, but verifies instance is still accessible
    echo -e "${BLUE}Verifying instance is accessible via SSM...${RESET}"
    if ! aws ssm start-session \
      --target "$INSTANCE_ID" \
      --document-name "AWS-StartInteractiveCommand" \
      --parameters command="echo Still connected to $(hostname) successfully" \
      --region "$REGION" \
      --profile "$PROFILE"; then
      echo -e "${RED}✘ Failed to connect using SSM after key update.${RESET}"
      if [[ "$FORCE" != "true" ]]; then
        echo -e "${RED}Key rotation may have caused issues. Use --force to proceed anyway.${RESET}"
        exit 1
      else
        echo -e "${YELLOW}Proceeding despite connection failure due to --force option.${RESET}"
      fi
    else
      echo -e "${GREEN}✓ SSM connection still working${RESET}"
      echo -e "${YELLOW}⚠ Note: SSM connection doesn't validate the new SSH key itself${RESET}"
    fi
  fi
}

# Function to update the secret
function update_secret {
  echo -e "${BLUE}Updating AWS Secrets Manager secret...${RESET}"
  
  local NEW_KEY_FILE="${OUTPUT_DIR}/${KEY_NAME}"
  
  # Read key files
  local PRIVATE_KEY=$(cat "$NEW_KEY_FILE")
  local PUBLIC_KEY=$(cat "${NEW_KEY_FILE}.pub")
  
  # Get existing secret to preserve metadata
  if ! SECRET_VALUE=$(aws secretsmanager get-secret-value \
    --secret-id "$SECRET_NAME" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query 'SecretString' \
    --output text); then
    echo -e "${RED}Error: Failed to retrieve existing secret.${RESET}"
    exit 1
  fi
  
  # Parse existing secret
  if ! echo "$SECRET_VALUE" | jq -e . >/dev/null 2>&1; then
    # Not valid JSON, create new structure
    if [[ -n "$INSTANCE_ID" ]]; then
      # Instance-specific key format
      SECRET_DATA=$(jq -n \
        --arg private_key "$PRIVATE_KEY" \
        --arg public_key "$PUBLIC_KEY" \
        --arg key_name "$KEY_NAME" \
        --arg instance_id "$INSTANCE_ID" \
        --arg env "${ENVIRONMENT:-unknown}" \
        --arg updated_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        '{
          "private_key": $private_key,
          "public_key": $public_key,
          "key_name": $key_name,
          "instance_id": $instance_id,
          "environment": $env,
          "updated_at": $updated_at,
          "key_type": "instance-specific",
          "rotated": true
        }')
    else
      # Environment-wide key format
      SECRET_DATA=$(jq -n \
        --arg private_key "$PRIVATE_KEY" \
        --arg public_key "$PUBLIC_KEY" \
        --arg key_name "$KEY_NAME" \
        --arg env "${ENVIRONMENT:-unknown}" \
        --arg updated_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        '{
          "private_key": $private_key,
          "public_key": $public_key,
          "key_name": $key_name,
          "environment": $env,
          "updated_at": $updated_at,
          "key_type": "environment-wide",
          "rotated": true
        }')
    fi
  else
    # Existing JSON, update while preserving structure
    SECRET_DATA=$(echo "$SECRET_VALUE" | jq \
      --arg private_key "$PRIVATE_KEY" \
      --arg public_key "$PUBLIC_KEY" \
      --arg updated_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
      '. + {
        "private_key": $private_key,
        "public_key": $public_key,
        "updated_at": $updated_at,
        "rotated": true,
        "previous_rotation": (.updated_at // "unknown")
      }')
  fi
  
  # Update the secret
  if ! aws secretsmanager update-secret \
    --secret-id "$SECRET_NAME" \
    --secret-string "$SECRET_DATA" \
    --region "$REGION" \
    --profile "$PROFILE"; then
    echo -e "${RED}Error: Failed to update secret.${RESET}"
    echo -e "${RED}The new key has been deployed but not saved to Secrets Manager.${RESET}"
    echo -e "${RED}Please manually update the secret or restore the backup.${RESET}"
    exit 1
  fi
  
  echo -e "${GREEN}✓ Secret updated successfully${RESET}"
}

# Function to update EC2 key pair if needed
function update_ec2_keypair {
  if [[ -z "$INSTANCE_ID" && -z "$ENVIRONMENT" ]]; then
    return
  fi
  
  echo -e "${BLUE}Checking if key needs to be imported to EC2...${RESET}"
  
  # Get existing secret to check metadata
  if ! SECRET_VALUE=$(aws secretsmanager get-secret-value \
    --secret-id "$SECRET_NAME" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query 'SecretString' \
    --output text); then
    echo -e "${RED}Error: Failed to retrieve updated secret.${RESET}"
    return
  fi
  
  # Extract EC2 key name if available
  local EC2_KEY_NAME=$(echo "$SECRET_VALUE" | jq -r '.key_name // empty')
  
  if [[ -n "$EC2_KEY_NAME" ]]; then
    echo -e "${BLUE}Found EC2 key name: ${EC2_KEY_NAME}${RESET}"
    
    # Check if key exists in EC2
    if aws ec2 describe-key-pairs --key-names "$EC2_KEY_NAME" --region "$REGION" --profile "$PROFILE" &>/dev/null; then
      echo -e "${BLUE}Existing EC2 key pair found. Deleting and recreating...${RESET}"
      
      # Delete the existing key
      if ! aws ec2 delete-key-pair --key-name "$EC2_KEY_NAME" --region "$REGION" --profile "$PROFILE"; then
        echo -e "${RED}Error: Failed to delete existing EC2 key pair.${RESET}"
        echo -e "${RED}You may need to manually import the new public key to EC2.${RESET}"
        return
      fi
    else
      echo -e "${BLUE}No existing EC2 key pair found. Will import fresh.${RESET}"
    fi
    
    # Import the new key
    local NEW_KEY_FILE="${OUTPUT_DIR}/${KEY_NAME}"
    if ! aws ec2 import-key-pair \
      --key-name "$EC2_KEY_NAME" \
      --public-key-material "fileb://${NEW_KEY_FILE}.pub" \
      --region "$REGION" \
      --profile "$PROFILE"; then
      echo -e "${RED}Error: Failed to import key pair to EC2.${RESET}"
      echo -e "${RED}You may need to manually import the new public key to EC2.${RESET}"
      return
    fi
    
    echo -e "${GREEN}✓ EC2 key pair updated successfully${RESET}"
  else
    echo -e "${YELLOW}No EC2 key name found in secret. Skipping EC2 key pair update.${RESET}"
  fi
}

# Function to perform cleanup
function cleanup {
  echo -e "${BLUE}Performing cleanup...${RESET}"
  
  # Keep the backup and generated keys by default
  # But provide instructions for secure cleanup
  
  echo -e "${YELLOW}Key rotation complete. For security:${RESET}"
  echo -e "${YELLOW}1. Verify the new key works with your instances${RESET}"
  echo -e "${YELLOW}2. Run these commands to securely delete sensitive files:${RESET}"
  echo -e "   rm ${BACKUP_DIR}/${KEY_NAME}-backup"
  echo -e "   rm ${OUTPUT_DIR}/${KEY_NAME}"
  echo -e "${YELLOW}3. Keep the public keys for reference:${RESET}"
  echo -e "   ${BACKUP_DIR}/${KEY_NAME}-backup.pub"
  echo -e "   ${OUTPUT_DIR}/${KEY_NAME}.pub"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  key="$1"

  case $key in
    -s|--secret)
      SECRET_NAME="$2"
      shift 2
      ;;
    -i|--instance)
      INSTANCE_ID="$2"
      shift 2
      ;;
    -e|--env)
      ENVIRONMENT="$2"
      shift 2
      ;;
    -h|--host)
      HOST="$2"
      shift 2
      ;;
    -n|--name)
      KEY_NAME="$2"
      shift 2
      ;;
    -t|--type)
      KEY_TYPE="$2"
      shift 2
      ;;
    -b|--bits)
      KEY_BITS="$2"
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
    -u|--user)
      USER="$2"
      shift 2
      ;;
    --no-ssm)
      USE_SSM=false
      shift
      ;;
    --no-verify)
      VERIFY=false
      shift
      ;;
    -f|--force)
      FORCE=true
      shift
      ;;
    --help)
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
check_ssh_requirements
validate_inputs
validate_aws_credentials
get_existing_key
verify_connectivity
generate_new_key
update_authorized_keys
verify_new_key
update_secret
update_ec2_keypair
cleanup

echo
echo -e "${BOLD}${GREEN}SSH key rotation completed successfully!${RESET}"
echo -e "${BOLD}Summary:${RESET}"
echo -e "  Secret:      ${SECRET_NAME}"
if [[ -n "$INSTANCE_ID" ]]; then
  echo -e "  Instance ID: ${INSTANCE_ID}"
fi
if [[ -n "$ENVIRONMENT" ]]; then
  echo -e "  Environment: ${ENVIRONMENT}"
fi
if [[ -n "$HOST" ]]; then
  echo -e "  Host:        ${HOST}"
fi
echo -e "  Old Key:     ${BACKUP_DIR}/${KEY_NAME}-backup"
echo -e "  New Key:     ${OUTPUT_DIR}/${KEY_NAME}"
echo -e ""
echo -e "${BOLD}Next steps:${RESET}"
echo -e "  1. Verify you can connect with the new key: ssh -i ${OUTPUT_DIR}/${KEY_NAME} ${USER}@${HOST:-<your-instance-ip>}"
echo -e "  2. Clean up the old key after confirming the new key works"

exit 0