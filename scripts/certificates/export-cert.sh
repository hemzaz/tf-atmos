#!/bin/bash
# ==============================================================================
# Certificate Export Script
# ==============================================================================
# This script exports certificates from AWS ACM and prepares them for use with
# Kubernetes secrets and AWS Secrets Manager.
# 
# IMPORTANT: This script requires the following:
# - AWS CLI installed and configured
# - jq installed (brew install jq / apt install jq)
# - openssl installed
# - Valid permissions to access ACM certificates
# ==============================================================================

set -eo pipefail

# Text formatting
BOLD="\033[1m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
RESET="\033[0m"

# Default values
OUTPUT_DIR="./exported-certificates"
SECRET_PREFIX="certificates"
SAVE_TO_SECRETS_MANAGER=false
REGION=""
CERT_ARN=""
SECRET_NAME=""

# Function to show usage
function show_usage {
  echo -e "${BOLD}ACM Certificate Export Script${RESET}"
  echo -e "Exports certificates from AWS ACM to various formats for use with Kubernetes and AWS services."
  echo
  echo -e "${BOLD}Usage:${RESET}"
  echo -e "  $0 -a CERTIFICATE_ARN [options]"
  echo
  echo -e "${BOLD}Required:${RESET}"
  echo -e "  -a, --arn ARN           ARN of the ACM certificate to export"
  echo
  echo -e "${BOLD}Options:${RESET}"
  echo -e "  -r, --region REGION     AWS region (defaults to AWS_REGION env var or aws configure default)"
  echo -e "  -o, --output DIR        Output directory for certificate files (default: ./exported-certificates)"
  echo -e "  -s, --secret-name NAME  Name of the secret in AWS Secrets Manager (default: certificates/domain-name)"
  echo -e "  -u, --upload            Upload certificate to AWS Secrets Manager"
  echo -e "  -h, --help              Show this help message"
  echo
  echo -e "${BOLD}Examples:${RESET}"
  echo -e "  $0 -a arn:aws:acm:us-west-2:123456789012:certificate/abcd1234-abcd-1234-abcd-1234abcd5678"
  echo -e "  $0 -a arn:aws:acm:us-west-2:123456789012:certificate/abcd1234 -o /tmp/certs -u"
  echo -e "  $0 -a arn:aws:acm:us-west-2:123456789012:certificate/abcd1234 -s custom/secret/path -u"
  echo
}

# Function to check required commands
function check_requirements {
  local MISSING_REQS=false
  
  echo -e "${BLUE}Checking requirements...${RESET}"
  
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
  
  if ! command -v openssl &> /dev/null; then
    echo -e "${RED}✘ openssl is not installed. Please install it.${RESET}"
    MISSING_REQS=true
  else
    echo -e "${GREEN}✓ openssl is installed${RESET}"
  fi
  
  if [[ "$MISSING_REQS" == "true" ]]; then
    echo -e "${RED}Please install missing requirements and try again.${RESET}"
    exit 1
  fi
}

# Function to validate AWS credentials
function validate_aws_credentials {
  echo -e "${BLUE}Validating AWS credentials...${RESET}"
  
  if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}✘ AWS credentials are not valid or not configured.${RESET}"
    echo -e "${YELLOW}Please run 'aws configure' or set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment variables.${RESET}"
    exit 1
  else
    local IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
    echo -e "${GREEN}✓ AWS credentials are valid${RESET}"
    echo -e "  Authenticated as: ${IDENTITY}"
    
    # Check if region is set
    if [[ -z "$REGION" ]]; then
      REGION=$(aws configure get region)
      if [[ -z "$REGION" ]]; then
        echo -e "${RED}✘ AWS region is not set. Please specify with -r/--region.${RESET}"
        exit 1
      fi
    fi
    echo -e "  Region: ${REGION}"
  fi
}

# Function to validate certificate ARN
function validate_certificate_arn {
  echo -e "${BLUE}Validating certificate ARN...${RESET}"
  
  if [[ -z "$CERT_ARN" ]]; then
    echo -e "${RED}✘ Certificate ARN is required. Use -a/--arn to specify it.${RESET}"
    show_usage
    exit 1
  fi
  
  # Extract the full ARN if shortened version was provided
  if [[ ! "$CERT_ARN" == arn:aws:acm:*:*:certificate/* ]]; then
    local CERT_ID=${CERT_ARN##*/}
    # If it's not a full ARN, try to find the full ARN
    local FULL_ARN=$(aws acm list-certificates --region "$REGION" --query "CertificateSummaryList[?contains(CertificateArn, '${CERT_ID}')].CertificateArn" --output text)
    
    if [[ -z "$FULL_ARN" ]]; then
      echo -e "${RED}✘ Could not find certificate with ID: $CERT_ID${RESET}"
      exit 1
    else
      CERT_ARN=$FULL_ARN
      echo -e "${GREEN}✓ Found full certificate ARN: $CERT_ARN${RESET}"
    fi
  else
    echo -e "${GREEN}✓ Certificate ARN format is valid${RESET}"
  fi
  
  # Check if certificate exists
  if ! aws acm describe-certificate --certificate-arn "$CERT_ARN" --region "$REGION" &> /dev/null; then
    echo -e "${RED}✘ Certificate not found or you don't have permission to access it.${RESET}"
    exit 1
  else
    echo -e "${GREEN}✓ Certificate exists and is accessible${RESET}"
  fi
}

# Function to get certificate details
function get_certificate_details {
  echo -e "${BLUE}Retrieving certificate details...${RESET}"
  
  local CERT_DETAILS=$(aws acm describe-certificate --certificate-arn "$CERT_ARN" --region "$REGION")
  
  # Get certificate domain name
  DOMAIN_NAME=$(echo "$CERT_DETAILS" | jq -r '.Certificate.DomainName')
  echo -e "${GREEN}✓ Certificate domain: $DOMAIN_NAME${RESET}"
  
  # Get alternative names
  SANS=$(echo "$CERT_DETAILS" | jq -r '.Certificate.SubjectAlternativeNames | join(", ")')
  if [[ ! -z "$SANS" ]]; then
    echo -e "${GREEN}✓ Subject Alternative Names: $SANS${RESET}"
  fi
  
  # Get status
  STATUS=$(echo "$CERT_DETAILS" | jq -r '.Certificate.Status')
  echo -e "${GREEN}✓ Certificate status: $STATUS${RESET}"
  
  if [[ "$STATUS" != "ISSUED" ]]; then
    echo -e "${RED}✘ Certificate is not in ISSUED state. Cannot export.${RESET}"
    exit 1
  fi
  
  # Get expiration date
  EXPIRY=$(echo "$CERT_DETAILS" | jq -r '.Certificate.NotAfter')
  if [[ ! -z "$EXPIRY" ]]; then
    echo -e "${GREEN}✓ Expires on: $EXPIRY${RESET}"
    
    # Check if certificate is expiring soon
    EXPIRY_SECONDS=$(date -j -f "%Y-%m-%dT%H:%M:%S%z" "$EXPIRY" +%s 2>/dev/null || date -d "$EXPIRY" +%s)
    NOW_SECONDS=$(date +%s)
    DAYS_REMAINING=$(( ($EXPIRY_SECONDS - $NOW_SECONDS) / 86400 ))
    
    if [[ $DAYS_REMAINING -lt 30 ]]; then
      echo -e "${RED}⚠ WARNING: Certificate expires in $DAYS_REMAINING days!${RESET}"
    elif [[ $DAYS_REMAINING -lt 60 ]]; then
      echo -e "${YELLOW}⚠ WARNING: Certificate expires in $DAYS_REMAINING days.${RESET}"
    fi
  fi
  
  # Set default secret name if not provided
  if [[ -z "$SECRET_NAME" ]]; then
    # Replace dots with hyphens and create a clean domain name
    CLEAN_DOMAIN=${DOMAIN_NAME//\./-}
    # Handle wildcard certificates
    CLEAN_DOMAIN=${CLEAN_DOMAIN//\*-/wildcard-}
    SECRET_NAME="${SECRET_PREFIX}/${CLEAN_DOMAIN}-cert"
    echo -e "${BLUE}Default secret name: $SECRET_NAME${RESET}"
  fi
}

# Function to export certificate
function export_certificate {
  echo -e "${BLUE}Exporting certificate...${RESET}"
  
  # Create output directory if it doesn't exist
  mkdir -p "$OUTPUT_DIR"
  
  # Export certificate and private key
  local CERT_EXPORT=$(aws acm export-certificate --certificate-arn "$CERT_ARN" --passphrase $(openssl rand -base64 32) --region "$REGION")
  
  # Extract certificate and private key
  echo "$CERT_EXPORT" | jq -r '.Certificate' > "$OUTPUT_DIR/$DOMAIN_NAME.crt"
  echo "$CERT_EXPORT" | jq -r '.PrivateKey' > "$OUTPUT_DIR/$DOMAIN_NAME.key"
  echo "$CERT_EXPORT" | jq -r '.CertificateChain' > "$OUTPUT_DIR/$DOMAIN_NAME-chain.crt"
  
  echo -e "${GREEN}✓ Certificate exported to $OUTPUT_DIR/$DOMAIN_NAME.crt${RESET}"
  echo -e "${GREEN}✓ Private key exported to $OUTPUT_DIR/$DOMAIN_NAME.key${RESET}"
  echo -e "${GREEN}✓ Certificate chain exported to $OUTPUT_DIR/$DOMAIN_NAME-chain.crt${RESET}"
  
  # Create kubernetes secret format
  echo -e "${BLUE}Creating Kubernetes secret format...${RESET}"
  
  # Create kubernetes secret file
  cat > "$OUTPUT_DIR/$DOMAIN_NAME-k8s-secret.yaml" << EOF
apiVersion: v1
kind: Secret
metadata:
  name: $(echo $DOMAIN_NAME | tr '.' '-')-tls
  namespace: istio-system
type: kubernetes.io/tls
data:
  tls.crt: $(cat "$OUTPUT_DIR/$DOMAIN_NAME.crt" | base64 | tr -d '\n')
  tls.key: $(cat "$OUTPUT_DIR/$DOMAIN_NAME.key" | base64 | tr -d '\n')
EOF
  
  echo -e "${GREEN}✓ Kubernetes secret created at $OUTPUT_DIR/$DOMAIN_NAME-k8s-secret.yaml${RESET}"
  
  # Create JSON format for Secrets Manager
  echo -e "${BLUE}Creating JSON format for Secrets Manager...${RESET}"
  
  # Create JSON file
  cat > "$OUTPUT_DIR/$DOMAIN_NAME-secret.json" << EOF
{
  "tls.crt": $(cat "$OUTPUT_DIR/$DOMAIN_NAME.crt" | jq -sR .),
  "tls.key": $(cat "$OUTPUT_DIR/$DOMAIN_NAME.key" | jq -sR .)
}
EOF
  
  echo -e "${GREEN}✓ Secrets Manager JSON created at $OUTPUT_DIR/$DOMAIN_NAME-secret.json${RESET}"
  
  # Set permissions on all sensitive files to be readable only by the owner
  chmod 600 "$OUTPUT_DIR/$DOMAIN_NAME.key"
  chmod 600 "$OUTPUT_DIR/$DOMAIN_NAME-secret.json"
  chmod 600 "$OUTPUT_DIR/$DOMAIN_NAME-k8s-secret.yaml"
  
  # Set a trap to ensure secure deletion of sensitive files on script exit/error
  trap 'echo -e "${YELLOW}Cleaning up sensitive files...${RESET}"; find "$OUTPUT_DIR" -name "*.key" -exec shred -u {} \; 2>/dev/null || true; find "$OUTPUT_DIR" -name "*-secret.json" -exec shred -u {} \; 2>/dev/null || true' EXIT INT TERM
}

# Function to upload to Secrets Manager
function upload_to_secrets_manager {
  echo -e "${BLUE}Uploading certificate to AWS Secrets Manager...${RESET}"
  
  # Check if secret exists
  if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region "$REGION" &> /dev/null; then
    echo -e "${YELLOW}Secret $SECRET_NAME already exists. Updating...${RESET}"
    aws secretsmanager update-secret --secret-id "$SECRET_NAME" \
      --secret-string "$(cat "$OUTPUT_DIR/$DOMAIN_NAME-secret.json")" \
      --region "$REGION"
  else
    echo -e "${GREEN}Creating new secret $SECRET_NAME...${RESET}"
    aws secretsmanager create-secret --name "$SECRET_NAME" \
      --description "TLS certificate for $DOMAIN_NAME" \
      --secret-string "$(cat "$OUTPUT_DIR/$DOMAIN_NAME-secret.json")" \
      --region "$REGION" \
      --tags Key=Domain,Value="$DOMAIN_NAME" Key=ManagedBy,Value="certificate-export-script"
  fi
  
  echo -e "${GREEN}✓ Certificate uploaded to Secrets Manager with name: $SECRET_NAME${RESET}"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  key="$1"

  case $key in
    -a|--arn)
      CERT_ARN="$2"
      shift # past argument
      shift # past value
      ;;
    -r|--region)
      REGION="$2"
      shift # past argument
      shift # past value
      ;;
    -o|--output)
      OUTPUT_DIR="$2"
      shift # past argument
      shift # past value
      ;;
    -s|--secret-name)
      SECRET_NAME="$2"
      shift # past argument
      shift # past value
      ;;
    -u|--upload)
      SAVE_TO_SECRETS_MANAGER=true
      shift # past argument
      ;;
    -h|--help)
      show_usage
      exit 0
      ;;
    *)    # unknown option
      echo -e "${RED}Unknown option: $1${RESET}"
      show_usage
      exit 1
      ;;
  esac
done

# Main execution
check_requirements
validate_aws_credentials
validate_certificate_arn
get_certificate_details
export_certificate

if [[ "$SAVE_TO_SECRETS_MANAGER" == "true" ]]; then
  upload_to_secrets_manager
fi

echo
echo -e "${BOLD}${GREEN}Certificate export completed successfully!${RESET}"
echo -e "${BOLD}Files created:${RESET}"
echo -e "  - Certificate: ${OUTPUT_DIR}/${DOMAIN_NAME}.crt"
echo -e "  - Private Key: ${OUTPUT_DIR}/${DOMAIN_NAME}.key"
echo -e "  - Certificate Chain: ${OUTPUT_DIR}/${DOMAIN_NAME}-chain.crt"
echo -e "  - Kubernetes Secret: ${OUTPUT_DIR}/${DOMAIN_NAME}-k8s-secret.yaml"
echo -e "  - Secrets Manager JSON: ${OUTPUT_DIR}/${DOMAIN_NAME}-secret.json"

if [[ "$SAVE_TO_SECRETS_MANAGER" == "true" ]]; then
  echo -e "${BOLD}Secret Manager:${RESET}"
  echo -e "  - Secret Name: ${SECRET_NAME}"
  echo -e "  - Region: ${REGION}"
fi

echo
echo -e "${BOLD}Usage with External Secrets:${RESET}"
echo -e "Add the following to your Kubernetes resources:"
echo
cat << EOF
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: $(echo $DOMAIN_NAME | tr '.' '-')-tls
  namespace: istio-system
spec:
  refreshInterval: "1h"
  secretStoreRef:
    name: aws-secretsmanager
    kind: ClusterSecretStore
  target:
    name: $(echo $DOMAIN_NAME | tr '.' '-')-tls
    creationPolicy: Owner
  data:
  - secretKey: tls.crt
    remoteRef:
      key: ${SECRET_NAME}
      property: tls.crt
  - secretKey: tls.key
    remoteRef:
      key: ${SECRET_NAME}
      property: tls.key
EOF

echo
echo -e "${BOLD}${YELLOW}SECURITY WARNING:${RESET}"
echo -e "${YELLOW}1. The private key has been saved locally. It will be automatically deleted when this script exits.${RESET}"
echo -e "${YELLOW}2. If you need to keep the local copies, press Ctrl+C now and copy them to a secure location.${RESET}"
echo -e "${YELLOW}3. For production usage, only keep certificates in AWS Secrets Manager.${RESET}"
echo -e "${YELLOW}4. Remember that the certificate files in $OUTPUT_DIR contain sensitive information.${RESET}"
echo -e ""
echo -e "${BOLD}Press Enter to exit (and delete local key files) or Ctrl+C to cancel automatic cleanup.${RESET}"
read -r
exit 0