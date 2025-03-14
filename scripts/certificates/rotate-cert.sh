#!/usr/bin/env bash
# DEPRECATED: This script has been replaced by the Python implementation in Gaia CLI.
# Please use "gaia certificate rotate" instead.
# See README in /gaia directory for usage details.
#
# Example:
#   gaia certificate rotate --secret <secret_name> --namespace <namespace> --acm-arn <acm_cert_arn>
#
# Or use the workflow:
#   gaia workflow rotate-certificate secret_name=<secret> namespace=<namespace> acm_arn=<acm_cert_arn>

echo "⚠️  This script is deprecated and will be removed in a future release."
echo "Please use 'gaia certificate rotate' instead."
echo "For more information, run 'gaia certificate rotate --help'"
echo "Redirecting to new command..."

# Extract parameters
SECRET_NAME=""
NAMESPACE=""
ACM_ARN=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --secret|-s)
      SECRET_NAME="$2"
      shift 2
      ;;
    --namespace|-n)
      NAMESPACE="$2"
      shift 2
      ;;
    --acm-arn|-a)
      ACM_ARN="$2"
      shift 2
      ;;
    *)
      echo "Warning: Unrecognized parameter: $1"
      shift
      ;;
  esac
done

# Redirect to gaia command with parameters
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Check if parameters were provided
if [[ -n "$SECRET_NAME" && -n "$NAMESPACE" ]]; then
  CMD="${REPO_ROOT}/bin/gaia certificate rotate --secret $SECRET_NAME --namespace $NAMESPACE"
  
  # Add optional ACM ARN if provided
  if [[ -n "$ACM_ARN" ]]; then
    CMD="$CMD --acm-arn $ACM_ARN"
  fi
  
  echo "Executing: $CMD"
  exec $CMD
else
  # No parameters, just show help
  exec "${REPO_ROOT}/bin/gaia" certificate rotate --help
fi
echo ""

set -euo pipefail

# Import utility functions with AWS retry mechanism
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/scripts/utils.sh"

# This script utilizes the aws_with_retry function from utils.sh to ensure robust handling
# of AWS API calls. All AWS CLI operations have been updated to use this retry mechanism
# with exponential backoff to handle transient errors including:
# - API rate limiting (Throttling)
# - Service unavailability
# - Network issues
# - Internal AWS errors
#
# Each AWS operation uses appropriate retry settings based on its criticality:
# - 3 attempts with 1s initial delay for standard operations
# - 4 attempts with 1-2s initial delay for certificate operations
# - 5 attempts with 2s initial delay for critical operations like secret updates

# Function to display usage information
usage() {
    echo "Usage: $0 -s <secret_name> -n <k8s_namespace> [-a <acm_certificate_arn>] [-r <region>] [-c <k8s_context>]"
    echo ""
    echo "Options:"
    echo "  -s SECRET_NAME   AWS Secret name in Secrets Manager"
    echo "  -n NAMESPACE     Kubernetes namespace for the secret"
    echo "  -a ARN           New AWS ACM Certificate ARN (optional)"
    echo "  -r REGION        AWS Region (default: current region)"
    echo "  -c CONTEXT       Kubernetes context (optional)"
    echo "  -k K8S_SECRET    Kubernetes secret name (default: derived from secret name)"
    echo "  -p PROFILE       AWS CLI profile (optional)"
    echo "  -h               Display this help message"
    exit 1
}

# Process command line arguments
while getopts "s:n:a:r:c:k:p:h" opt; do
    case "${opt}" in
        s) SECRET_NAME=${OPTARG} ;;
        n) NAMESPACE=${OPTARG} ;;
        a) ACM_CERT_ARN=${OPTARG} ;;
        r) AWS_REGION=${OPTARG} ;;
        c) KUBE_CONTEXT=${OPTARG} ;;
        k) K8S_SECRET=${OPTARG} ;;
        p) AWS_PROFILE=${OPTARG} ;;
        h) usage ;;
        *) usage ;;
    esac
done

# Check required parameters
if [ -z "${SECRET_NAME:-}" ] || [ -z "${NAMESPACE:-}" ]; then
    echo "Error: Missing required parameters"
    usage
fi

# Set default region if not provided
if [ -z "${AWS_REGION:-}" ]; then
    # Get region using retry mechanism
    AWS_REGION=$(aws_with_retry 3 1 aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        echo "Error: AWS region not specified and not found in AWS CLI config"
        exit 1
    fi
fi

# Set K8S_SECRET to SECRET_NAME basename if not specified
if [ -z "${K8S_SECRET:-}" ]; then
    K8S_SECRET=$(basename "$SECRET_NAME")
fi

# Set AWS profile if specified
PROFILE_OPT=""
if [ -n "${AWS_PROFILE:-}" ]; then
    PROFILE_OPT="--profile $AWS_PROFILE"
fi

# Set Kubernetes context if specified
CONTEXT_OPT=""
if [ -n "${KUBE_CONTEXT:-}" ]; then
    CONTEXT_OPT="--context $KUBE_CONTEXT"
fi

echo "Starting certificate rotation process..."
echo "AWS Secret: $SECRET_NAME"
echo "Region: $AWS_REGION"
echo "Kubernetes Namespace: $NAMESPACE"
echo "Kubernetes Secret: $K8S_SECRET"

# Check if the AWS secret exists with retry mechanism
echo "Checking if secret exists in AWS Secrets Manager..."
# Build command array for aws_with_retry
CHECK_SECRET_CMD=(aws secretsmanager describe-secret
    --secret-id "$SECRET_NAME"
    --region "$AWS_REGION")

# Add profile option if specified
[ -n "$PROFILE_OPT" ] && CHECK_SECRET_CMD+=($PROFILE_OPT)

# Execute with retry - 3 attempts, starting with 1 second delay
if ! aws_with_retry 3 1 "${CHECK_SECRET_CMD[@]}" &>/dev/null; then
    echo "Error: Secret $SECRET_NAME not found in AWS Secrets Manager after multiple attempts"
    exit 1
fi

# If a new ACM ARN is provided, update the certificate
if [ -n "${ACM_CERT_ARN:-}" ]; then
    echo "New ACM certificate ARN provided: $ACM_CERT_ARN"
    
    # Get certificate details from AWS ACM
    echo "Fetching certificate details from ACM..."
    # Build command array for aws_with_retry
    DESCRIBE_CERT_CMD=(aws acm describe-certificate
        --certificate-arn "$ACM_CERT_ARN"
        --region "$AWS_REGION")
    
    # Add profile option if specified
    [ -n "$PROFILE_OPT" ] && DESCRIBE_CERT_CMD+=($PROFILE_OPT)
    
    # Execute with retry - 4 attempts, starting with 1 second delay
    CERT_DETAILS=$(aws_with_retry 4 1 "${DESCRIBE_CERT_CMD[@]}")
    
    # Extract domain name and other details
    DOMAIN_NAME=$(echo "$CERT_DETAILS" | jq -r '.Certificate.DomainName')
    CERT_STATUS=$(echo "$CERT_DETAILS" | jq -r '.Certificate.Status')
    EXPIRY_DATE=$(echo "$CERT_DETAILS" | jq -r '.Certificate.NotAfter // empty')
    CERT_TYPE=$(echo "$CERT_DETAILS" | jq -r '.Certificate.Type // "IMPORTED"')
    
    # Validate certificate
    if [ "$CERT_STATUS" != "ISSUED" ]; then
        echo "Error: Certificate is not in ISSUED state. Current status: $CERT_STATUS"
        exit 1
    fi
    
    # Convert AWS timestamp to human-readable date if it exists
    EXPIRY_DATE_HUMAN=""
    if [ -n "$EXPIRY_DATE" ]; then
        # Cross-platform timestamp conversion that works on both Linux and macOS
        if command -v jq &>/dev/null; then
            # Use jq for more reliable cross-platform date formatting (most reliable)
            # Convert AWS timestamp to unix epoch and format using jq's strftime
            EPOCH_SECONDS=$(echo "$EXPIRY_DATE" | cut -d. -f1)
            EXPIRY_DATE_HUMAN=$(echo "$EPOCH_SECONDS" | jq -r 'tonumber | strftime("%Y-%m-%d %H:%M:%S")')
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS date command format
            EXPIRY_DATE_HUMAN=$(date -j -f %s $(echo "$EXPIRY_DATE" | cut -d. -f1) "+%Y-%m-%d %H:%M:%S")
        elif [[ "$OSTYPE" == "linux"* ]] || [[ "$OSTYPE" == "linux-gnu"* ]]; then
            # Linux date command format
            EXPIRY_DATE_HUMAN=$(date -d "@$(echo "$EXPIRY_DATE" | cut -d. -f1)" "+%Y-%m-%d %H:%M:%S")
        else
            # Generic fallback for other platforms
            echo "Warning: Unable to format date on this platform ($OSTYPE). Using raw value."
            EXPIRY_DATE_HUMAN="$EXPIRY_DATE"
        fi
    fi
    
    echo "Domain: $DOMAIN_NAME"
    echo "Status: $CERT_STATUS"
    echo "Type: $CERT_TYPE"
    echo "Expires: $EXPIRY_DATE_HUMAN"
    
    # Get certificate from ACM with retry mechanism
    # Build command array for aws_with_retry
    GET_CERT_CMD=(aws acm get-certificate
        --certificate-arn "$ACM_CERT_ARN"
        --region "$AWS_REGION")
        
    # Add profile option if specified
    [ -n "$PROFILE_OPT" ] && GET_CERT_CMD+=($PROFILE_OPT)
    
    # Execute with retry - 4 attempts, starting with 1 second delay
    CERT_DATA=$(aws_with_retry 4 1 "${GET_CERT_CMD[@]}")
        
    # Validate that we received certificate data
    if [ -z "$CERT_DATA" ]; then
        echo "Error: Failed to retrieve certificate data from ACM"
        exit 1
    fi
    
    # Get certificate and chain, handling possible base64 encoding
    CERTIFICATE=$(echo "$CERT_DATA" | jq -r '.Certificate')
    CERTIFICATE_CHAIN=$(echo "$CERT_DATA" | jq -r '.CertificateChain')
    
    # Validate certificate data was extracted
    if [ -z "$CERTIFICATE" ]; then
        echo "Error: Failed to extract certificate from ACM response"
        exit 1
    fi
    
    # Check if certificate is base64-encoded and decode if needed
    if [[ "$CERTIFICATE" =~ ^[A-Za-z0-9+/]+={0,2}$ ]] && ! [[ "$CERTIFICATE" =~ "BEGIN CERTIFICATE" ]]; then
        echo "Certificate appears to be base64-encoded, decoding..."
        CERTIFICATE=$(echo "$CERTIFICATE" | base64 -d)
        
        if [ -z "$CERTIFICATE_CHAIN" ] || [[ "$CERTIFICATE_CHAIN" =~ ^[A-Za-z0-9+/]+={0,2}$ ]]; then
            CERTIFICATE_CHAIN=$(echo "$CERTIFICATE_CHAIN" | base64 -d)
        fi
    fi
    
    # Create a temporary directory with appropriate permissions for certificate files
    TEMP_DIR=$(mktemp -d)
    
    # Secure the temp directory with strict permissions
    chmod 700 "$TEMP_DIR"
    
    # Set up comprehensive trap handlers to ensure cleanup in all exit scenarios
    # This ensures temp files are removed even with forced terminations
    cleanup() {
        echo "Cleaning up temporary files in $TEMP_DIR"
        rm -rf "$TEMP_DIR"
    }
    
    # Handle normal exit
    trap cleanup EXIT
    
    # Handle other signals (INT = Ctrl+C, TERM = termination, HUP = terminal closed, 
    # QUIT = quit signal, ABRT = abort, SEGV = segmentation fault, PIPE = broken pipe)
    trap 'cleanup; echo "Caught signal - exiting"; exit 1' HUP INT QUIT TERM ABRT SEGV PIPE
    
    # Save certificate to file and ensure proper certificate chain order (leaf → intermediate → root)
    echo "$CERTIFICATE" > "$TEMP_DIR/tls.crt"
    echo "$CERTIFICATE_CHAIN" > "$TEMP_DIR/chain.crt"
    
    # Validate certificate chain order
    if grep -q "BEGIN CERTIFICATE" "$TEMP_DIR/chain.crt"; then
        # Create proper chain with leaf first, then intermediates, then root
        if ! openssl verify -untrusted "$TEMP_DIR/chain.crt" "$TEMP_DIR/tls.crt" >/dev/null 2>&1; then
            echo "⚠️ Certificate chain validation failed. Attempting to fix chain order..."
            # Extract individual certificates from chain
            csplit -q -f "$TEMP_DIR/cert-" "$TEMP_DIR/chain.crt" '/-----BEGIN CERTIFICATE-----/' '{*}'
            # Create new chain with proper order
            cat "$TEMP_DIR/tls.crt" "$TEMP_DIR"/cert-* > "$TEMP_DIR/fullchain.crt"
        else
            # Chain is valid, create fullchain in proper order
            cat "$TEMP_DIR/tls.crt" "$TEMP_DIR/chain.crt" > "$TEMP_DIR/fullchain.crt"
        fi
    else
        # No chain certificates, just use the leaf certificate
        cp "$TEMP_DIR/tls.crt" "$TEMP_DIR/fullchain.crt"
    fi
    
    # For AWS-managed certificates, we need the private key
    if [ "$CERT_TYPE" != "IMPORTED" ]; then
        echo "This is an AWS-managed certificate. Private key is not available from ACM."
        
        # Non-interactive mode: check if PRIVATE_KEY_FILE was provided via environment variable
        if [ -n "${PRIVATE_KEY_FILE:-}" ]; then
            KEY_PATH="${PRIVATE_KEY_FILE}"
            echo "Using private key from environment variable: $KEY_PATH"
        else
            # Check if a command line argument was provided
            if [ -n "${KEY_PATH:-}" ]; then
                echo "Using private key from command line: $KEY_PATH"
            else
                # Only prompt interactively if not in CI mode
                if [ "${CI_MODE:-false}" != "true" ]; then
                    read -p "Enter path to the private key file: " KEY_PATH
                else
                    echo "Error: In CI mode, private key file must be provided via PRIVATE_KEY_FILE environment variable or KEY_PATH argument."
                    exit 1
                fi
            fi
        fi
        
        if [ ! -f "$KEY_PATH" ]; then
            echo "Error: Private key file not found at $KEY_PATH."
            exit 1
        fi
        
        # Copy the private key
        cp "$KEY_PATH" "$TEMP_DIR/tls.key"
    else
        echo "This is an imported certificate. You may need to provide the original private key."
        
        # Non-interactive mode: check if PRIVATE_KEY_FILE was provided via environment variable
        if [ -n "${PRIVATE_KEY_FILE:-}" ]; then
            KEY_PATH="${PRIVATE_KEY_FILE}"
            echo "Using private key from environment variable: $KEY_PATH"
            
            if [ ! -f "$KEY_PATH" ]; then
                echo "Error: Private key file not found at $KEY_PATH."
                exit 1
            fi
            
            # Copy the private key
            cp "$KEY_PATH" "$TEMP_DIR/tls.key"
        else
            # Check if a command line argument was provided
            if [ -n "${KEY_PATH:-}" ]; then
                echo "Using private key from command line: $KEY_PATH"
                
                if [ ! -f "$KEY_PATH" ]; then
                    echo "Error: Private key file not found at $KEY_PATH."
                    exit 1
                fi
                
                # Copy the private key
                cp "$KEY_PATH" "$TEMP_DIR/tls.key"
            else
                # Only prompt interactively if not in CI mode
                if [ "${CI_MODE:-false}" != "true" ]; then
                    read -p "Enter path to the private key file (or press Enter to keep existing key): " KEY_PATH
                    if [ -n "$KEY_PATH" ]; then
                        if [ ! -f "$KEY_PATH" ]; then
                            echo "Error: Private key file not found at $KEY_PATH."
                            exit 1
                        fi
                        
                        # Copy the private key
                        cp "$KEY_PATH" "$TEMP_DIR/tls.key"
                    else
                        echo "Using existing private key from the secret..."
                        
                        # Get existing secret with retry mechanism
                        # Build command array for aws_with_retry
                        GET_SECRET_CMD=(aws secretsmanager get-secret-value
                            --secret-id "$SECRET_NAME"
                            --region "$AWS_REGION"
                            --query 'SecretString'
                            --output text)
                        
                        # Add profile option if specified
                        [ -n "$PROFILE_OPT" ] && GET_SECRET_CMD+=($PROFILE_OPT)
                        
                        # Execute with retry - 4 attempts, starting with 2 second delay
                        SECRET_VALUE=$(aws_with_retry 4 2 "${GET_SECRET_CMD[@]}")
                        
                        # Extract private key
                        echo "$SECRET_VALUE" | jq -r '.["tls.key"] // empty' > "$TEMP_DIR/tls.key"
                        
                        if [ ! -s "$TEMP_DIR/tls.key" ]; then
                            echo "Error: Could not extract private key from existing secret."
                            exit 1
                        fi
                    fi
                fi
                
                # Create JSON for the updated secret
                cat > "$TEMP_DIR/secret.json" << EOF
{
  "tls.crt": $(cat "$TEMP_DIR/fullchain.crt" | jq -sR .),
  "tls.key": $(cat "$TEMP_DIR/tls.key" | jq -sR .),
  "domain": "$DOMAIN_NAME",
  "expiry": "$EXPIRY_DATE_HUMAN",
  "acm_arn": "$ACM_CERT_ARN",
  "updated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
                
                # Update the secret in AWS Secrets Manager
    echo "Updating secret in AWS Secrets Manager: $SECRET_NAME"
    
    # Use aws_with_retry for reliable AWS API calls with retries
    # Using 5 attempts with 2-second initial delay
    UPDATE_CMD=(aws secretsmanager update-secret
        --secret-id "$SECRET_NAME"
        --secret-string "$(cat "$TEMP_DIR/secret.json")"
        --region "$AWS_REGION")
    
    # Add profile option if specified
    [ -n "$PROFILE_OPT" ] && UPDATE_CMD+=($PROFILE_OPT)
    
    # Capture the output of the update command to validate success
    UPDATE_RESULT=$(aws_with_retry 5 2 "${UPDATE_CMD[@]}" 2>&1)
    
    # Check if the update was successful
    if [ $? -ne 0 ]; then
        echo "❌ Failed to update secret in AWS Secrets Manager after multiple attempts:"
        echo "$UPDATE_RESULT"
        exit 1
    fi
    
    # Verify the secret was actually updated by checking its metadata
    # Using 3 attempts with 1-second initial delay for verification
    VERIFY_CMD=(aws secretsmanager describe-secret
        --secret-id "$SECRET_NAME"
        --region "$AWS_REGION")
    
    # Add profile option if specified
    [ -n "$PROFILE_OPT" ] && VERIFY_CMD+=($PROFILE_OPT)
    
    VERIFY_RESULT=$(aws_with_retry 3 1 "${VERIFY_CMD[@]}" 2>&1)
    
    if [ $? -ne 0 ]; then
        echo "⚠️ Secret was updated but verification failed:"
        echo "$VERIFY_RESULT"
        echo "Please verify the secret manually."
    else
        # Check the LastChangedDate is recent (within last 60 seconds)
        # Use a more robust way to handle various date formats
        LAST_CHANGED=$(echo "$VERIFY_RESULT" | jq -r '.LastChangedDate')
        NOW_EPOCH=$(date +%s)
        
        # Handle timestamps more robustly
        if [[ "$LAST_CHANGED" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            # Already an epoch timestamp
            LAST_CHANGED_EPOCH=$(echo "$LAST_CHANGED" | cut -d. -f1)
        else
            # Convert ISO format to epoch using platform-specific approach
            if command -v jq &>/dev/null; then
                # Use jq if available (most reliable)
                LAST_CHANGED_EPOCH=$(echo "$LAST_CHANGED" | jq -r 'strptime("%Y-%m-%dT%H:%M:%SZ") | tostring | split(".") | .[0]')
            elif [[ "$OSTYPE" == "darwin"* ]]; then
                # macOS approach
                LAST_CHANGED_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$LAST_CHANGED" +%s 2>/dev/null || echo "$NOW_EPOCH")
            else
                # Linux approach
                LAST_CHANGED_EPOCH=$(date -d "$LAST_CHANGED" +%s 2>/dev/null || echo "$NOW_EPOCH")
            fi
        fi
        
        if [ $((NOW_EPOCH - LAST_CHANGED_EPOCH)) -gt 60 ]; then
            echo "⚠️ Secret update may not have been applied. LastChangedDate is not recent."
            echo "Please verify the secret was updated correctly."
        else
            echo "✅ Secret successfully updated in AWS Secrets Manager"
        fi
    fi
fi

# Check if ExternalSecret exists in Kubernetes
echo "Checking for ExternalSecret in Kubernetes..."
if ! kubectl get externalsecret -n "$NAMESPACE" $CONTEXT_OPT 2>/dev/null | grep -q "$K8S_SECRET"; then
    echo "ExternalSecret not found. Creating it now..."
    
    # Create the ExternalSecret
    cat > /tmp/external-secret.yaml << EOF
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: $K8S_SECRET
  namespace: $NAMESPACE
spec:
  refreshInterval: "1h"
  secretStoreRef:
    name: aws-certificate-store
    kind: ClusterSecretStore
  target:
    name: $K8S_SECRET
    creationPolicy: Owner
    template:
      type: kubernetes.io/tls
  data:
  - secretKey: tls.crt
    remoteRef:
      key: "$SECRET_NAME"
      property: tls.crt
  - secretKey: tls.key
    remoteRef:
      key: "$SECRET_NAME"
      property: tls.key
EOF
    
    kubectl apply -f /tmp/external-secret.yaml $CONTEXT_OPT
    rm /tmp/external-secret.yaml
    
    echo "✅ ExternalSecret created"
else
    echo "ExternalSecret already exists. Triggering a refresh..."
    
    # Check if ExternalSecret actually exists before annotating
    if kubectl get externalsecret "$K8S_SECRET" -n "$NAMESPACE" $CONTEXT_OPT &>/dev/null; then
        # Add annotation to force refresh
        TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        kubectl annotate externalsecret "$K8S_SECRET" -n "$NAMESPACE" $CONTEXT_OPT \
            externalsecrets.io/force-sync="$TIMESTAMP" \
            --overwrite
        
        echo "✅ ExternalSecret refresh triggered"
    else
        echo "⚠️ ExternalSecret exists but couldn't be accessed. Refresh not triggered."
        echo "This could be due to permission issues or a namespace mismatch."
    fi
    
fi

# Wait for the secret refresh to complete with timeout and validation
echo "Waiting for secret refresh to complete..."
TIMEOUT=60
INTERVAL=2
ELAPSED=0

while [ $ELAPSED -lt $TIMEOUT ]; do
    # Check if the secret exists and verify it has been updated
    if kubectl get secret "$K8S_SECRET" -n "$NAMESPACE" $CONTEXT_OPT &>/dev/null; then
        # Get the last update time of the secret
        SECRET_UPDATE_TIME=$(kubectl get secret "$K8S_SECRET" -n "$NAMESPACE" $CONTEXT_OPT -o jsonpath='{.metadata.creationTimestamp}')
        # Convert to epoch for comparison
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS date command format
            SECRET_UPDATE_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$SECRET_UPDATE_TIME" +%s 2>/dev/null)
        else
            # Linux date command format
            SECRET_UPDATE_EPOCH=$(date -d "$SECRET_UPDATE_TIME" +%s 2>/dev/null)
        fi
        
        # Get current time
        CURRENT_EPOCH=$(date +%s)
        # If the secret was updated within the last minute, consider it done
        if [ $((CURRENT_EPOCH - SECRET_UPDATE_EPOCH)) -lt 120 ]; then
            echo "✅ Secret was successfully refreshed"
            break
        fi
    fi
    
    # Sleep and increment counter
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
    echo -n "."
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "⚠️ Timed out waiting for secret refresh. The ExternalSecret may still be processing."
fi

# Check if Kubernetes secret exists and is up-to-date
echo "Checking Kubernetes secret status..."
if ! kubectl get secret "$K8S_SECRET" -n "$NAMESPACE" $CONTEXT_OPT &>/dev/null; then
    echo "⚠️ Kubernetes secret doesn't exist yet. It may take a moment to be created."
else
    SECRET_AGE=$(kubectl get secret "$K8S_SECRET" -n "$NAMESPACE" $CONTEXT_OPT -o jsonpath='{.metadata.creationTimestamp}')
    echo "Kubernetes secret exists (created at $SECRET_AGE)"
fi

# Check for pods that mount this secret
echo "Checking for pods that mount this secret..."
PODS_WITH_SECRET=$(kubectl get pods -n "$NAMESPACE" $CONTEXT_OPT -o json | \
    jq -r ".items[] | select(.spec.volumes[]?.secret?.secretName == \"$K8S_SECRET\") | .metadata.name")

if [ -n "$PODS_WITH_SECRET" ]; then
    echo "The following pods mount this secret and may need a restart:"
    echo "$PODS_WITH_SECRET"
    
    # Handle pod restart based on AUTO_RESTART_PODS or CI_MODE
    AUTO_RESTART="false"
    if [ "${AUTO_RESTART_PODS:-false}" == "true" ] || [ "${CI_MODE:-false}" == "true" ]; then
        echo "Auto-restarting pods is enabled via environment variable."
        AUTO_RESTART="true"
    elif [ "${CI_MODE:-false}" != "true" ]; then
        # Only prompt if not in CI mode
        read -p "Do you want to restart these pods to pick up the new certificate? (y/n): " RESTART_CHOICE
        if [[ "$RESTART_CHOICE" == "y" || "$RESTART_CHOICE" == "Y" ]]; then
            AUTO_RESTART="true"
        fi
    fi
    
    if [[ "$AUTO_RESTART" == "true" ]]; then
        for POD in $PODS_WITH_SECRET; do
            echo "Restarting pod: $POD"
            kubectl delete pod "$POD" -n "$NAMESPACE" $CONTEXT_OPT
        done
        echo "✅ Pods restarted"
    else
        echo "Pods were not restarted. You may need to restart them manually."
    fi
else
    echo "No pods found that directly mount this secret."
fi

# Pass control to the new Python implementation
if command -v gaia >/dev/null 2>&1; then
  echo "Using Gaia CLI for certificate rotation..."
  
  # Convert arguments to gaia format
  GAIA_ARGS=()
  [[ -n "${SECRET_NAME:-}" ]] && GAIA_ARGS+=(--secret "$SECRET_NAME")
  [[ -n "${NAMESPACE:-}" ]] && GAIA_ARGS+=(--namespace "$NAMESPACE")
  [[ -n "${ACM_CERT_ARN:-}" ]] && GAIA_ARGS+=(--acm-arn "$ACM_CERT_ARN")
  [[ -n "${AWS_REGION:-}" ]] && GAIA_ARGS+=(--region "$AWS_REGION")
  [[ -n "${KUBE_CONTEXT:-}" ]] && GAIA_ARGS+=(--context "$KUBE_CONTEXT")
  [[ -n "${K8S_SECRET:-}" ]] && GAIA_ARGS+=(--k8s-secret "$K8S_SECRET")
  [[ -n "${AWS_PROFILE:-}" ]] && GAIA_ARGS+=(--profile "$AWS_PROFILE")
  [[ -n "${PRIVATE_KEY_FILE:-}" ]] && GAIA_ARGS+=(--key-path "$PRIVATE_KEY_FILE")
  [[ "${AUTO_RESTART_PODS:-false}" == "true" ]] && GAIA_ARGS+=(--restart-pods)
  
  # Execute gaia command
  exec gaia certificate rotate "${GAIA_ARGS[@]}"
else
  echo "⚠️  Gaia CLI not found. Please install it to use the new certificate rotation functionality."
  echo "Certificate rotation completed with legacy script. This script will be removed in a future release."
fi