#!/usr/bin/env bash
# Certificate Rotation Script
# This script helps with rotation of certificates in AWS ACM and updates Kubernetes secrets

set -euo pipefail

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
    AWS_REGION=$(aws configure get region)
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

# Check if the AWS secret exists
echo "Checking if secret exists in AWS Secrets Manager..."
if ! aws secretsmanager describe-secret \
    --secret-id "$SECRET_NAME" \
    --region "$AWS_REGION" \
    $PROFILE_OPT &>/dev/null; then
    echo "Error: Secret $SECRET_NAME not found in AWS Secrets Manager"
    exit 1
fi

# If a new ACM ARN is provided, update the certificate
if [ -n "${ACM_CERT_ARN:-}" ]; then
    echo "New ACM certificate ARN provided: $ACM_CERT_ARN"
    
    # Get certificate details from AWS ACM
    echo "Fetching certificate details from ACM..."
    CERT_DETAILS=$(aws acm describe-certificate \
        --certificate-arn "$ACM_CERT_ARN" \
        --region "$AWS_REGION" \
        $PROFILE_OPT)
    
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
        EXPIRY_DATE_HUMAN=$(date -r $(echo "$EXPIRY_DATE" | cut -d. -f1) "+%Y-%m-%d %H:%M:%S")
    fi
    
    echo "Domain: $DOMAIN_NAME"
    echo "Status: $CERT_STATUS"
    echo "Type: $CERT_TYPE"
    echo "Expires: $EXPIRY_DATE_HUMAN"
    
    # Get certificate from ACM
    CERT_DATA=$(aws acm get-certificate \
        --certificate-arn "$ACM_CERT_ARN" \
        --region "$AWS_REGION" \
        $PROFILE_OPT)
    
    CERTIFICATE=$(echo "$CERT_DATA" | jq -r '.Certificate')
    CERTIFICATE_CHAIN=$(echo "$CERT_DATA" | jq -r '.CertificateChain')
    
    # Create a temporary directory for certificate files
    TEMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TEMP_DIR"' EXIT
    
    # Save certificate to file
    echo "$CERTIFICATE" > "$TEMP_DIR/tls.crt"
    echo "$CERTIFICATE_CHAIN" > "$TEMP_DIR/chain.crt"
    cat "$TEMP_DIR/tls.crt" "$TEMP_DIR/chain.crt" > "$TEMP_DIR/fullchain.crt"
    
    # For AWS-managed certificates, we need the private key from the user
    if [ "$CERT_TYPE" != "IMPORTED" ]; then
        echo "This is an AWS-managed certificate. Private key is not available from ACM."
        echo "You need to provide the private key manually."
        
        read -p "Enter path to the private key file: " KEY_PATH
        if [ ! -f "$KEY_PATH" ]; then
            echo "Error: Private key file not found."
            exit 1
        fi
        
        # Copy the private key
        cp "$KEY_PATH" "$TEMP_DIR/tls.key"
    else
        echo "This is an imported certificate. You may need to provide the original private key."
        
        read -p "Enter path to the private key file (or press Enter to keep existing key): " KEY_PATH
        if [ -n "$KEY_PATH" ]; then
            if [ ! -f "$KEY_PATH" ]; then
                echo "Error: Private key file not found."
                exit 1
            fi
            
            # Copy the private key
            cp "$KEY_PATH" "$TEMP_DIR/tls.key"
        else
            echo "Using existing private key from the secret..."
            
            # Get existing secret
            SECRET_VALUE=$(aws secretsmanager get-secret-value \
                --secret-id "$SECRET_NAME" \
                --region "$AWS_REGION" \
                $PROFILE_OPT \
                --query 'SecretString' \
                --output text)
            
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
    aws secretsmanager update-secret \
        --secret-id "$SECRET_NAME" \
        --secret-string "$(cat "$TEMP_DIR/secret.json")" \
        --region "$AWS_REGION" \
        $PROFILE_OPT
        
    echo "✅ Secret updated in AWS Secrets Manager"
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
    
    # Add annotation to force refresh
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    kubectl annotate externalsecret "$K8S_SECRET" -n "$NAMESPACE" $CONTEXT_OPT \
        externalsecrets.io/force-sync="$TIMESTAMP" \
        --overwrite
    
    echo "✅ ExternalSecret refresh triggered"
fi

# Wait for the refresh to complete
echo "Waiting for secret refresh to complete..."
sleep 5

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
    
    read -p "Do you want to restart these pods to pick up the new certificate? (y/n): " RESTART_PODS
    if [[ "$RESTART_PODS" == "y" || "$RESTART_PODS" == "Y" ]]; then
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

echo "Certificate rotation process completed successfully!"