#!/bin/bash
set -e

# Certificate Monitoring Script
# This script monitors SSL/TLS certificates in AWS ACM, AWS Secrets Manager, and SSH keys
# and sends alerts for expiring certificates and keys

# Text formatting
BOLD="\033[1m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
RESET="\033[0m"

# Default values
REGION=""
PROFILE="default"
WARNING_DAYS=30
CRITICAL_DAYS=14
CHECK_ACM=true
CHECK_SECRETS=true
CHECK_SSH_KEYS=true
OUTPUT_FORMAT="text"
NOTIFICATION_CHANNEL=""
SLACK_WEBHOOK=""
SNS_TOPIC=""
EMAIL=""
JIRA_URL=""
JIRA_USER=""
JIRA_API_TOKEN=""
JIRA_PROJECT=""
JSON_OUTPUT_FILE=""

# Display usage information
function show_usage {
  echo -e "${BOLD}Certificate Monitoring Script${RESET}"
  echo -e "Monitors SSL/TLS certificates and SSH keys in AWS services and alerts on expiration"
  echo
  echo -e "${BOLD}Usage:${RESET}"
  echo -e "  $0 [options]"
  echo
  echo -e "${BOLD}Options:${RESET}"
  echo -e "  -r, --region REGION          AWS region (default: current AWS CLI region)"
  echo -e "  -p, --profile PROFILE        AWS profile (default: default)"
  echo -e "  -w, --warning DAYS           Warning threshold in days (default: 30)"
  echo -e "  -c, --critical DAYS          Critical threshold in days (default: 14)"
  echo -e "      --no-acm                 Skip checking ACM certificates"
  echo -e "      --no-secrets             Skip checking Secrets Manager certificates"
  echo -e "      --no-ssh                 Skip checking SSH keys"
  echo -e "  -o, --output FORMAT          Output format (text, json, html, default: text)"
  echo -e "  -f, --file FILE              JSON output file (for json format only)"
  echo -e "      --slack WEBHOOK          Send alerts to Slack webhook URL"
  echo -e "      --sns TOPIC              Send alerts to SNS topic ARN"
  echo -e "      --email ADDRESS          Send alerts to email address"
  echo -e "      --jira URL USER TOKEN    Create Jira tickets for critical certificates"
  echo -e "      --jira-project KEY       Jira project key for creating tickets"
  echo -e "  -h, --help                   Show this help"
  echo
  echo -e "${BOLD}Examples:${RESET}"
  echo -e "  # Basic usage"
  echo -e "  $0 -r us-west-2 -p prod-profile"
  echo
  echo -e "  # Set custom thresholds and Slack notifications"
  echo -e "  $0 -w 45 -c 21 --slack https://hooks.slack.com/services/XXX/YYY/ZZZ"
  echo
  echo -e "  # Generate JSON report and send to SNS"
  echo -e "  $0 --output json -f certificates-report.json --sns arn:aws:sns:us-west-2:123456789012:CertAlerts"
  echo
  exit 1
}

# Function to check requirements
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
  
  if [[ "$MISSING_REQS" == "true" ]]; then
    echo -e "${RED}Please install missing requirements and try again.${RESET}"
    exit 1
  fi
}

# Function to validate inputs
function validate_inputs {
  # If region not provided, use AWS CLI default
  if [[ -z "$REGION" ]]; then
    REGION=$(aws configure get region --profile "$PROFILE")
    if [[ -z "$REGION" ]]; then
      echo -e "${RED}Error: AWS region not specified and not found in AWS CLI config.${RESET}"
      exit 1
    fi
  fi
  
  # Validate output format
  if [[ "$OUTPUT_FORMAT" != "text" && "$OUTPUT_FORMAT" != "json" && "$OUTPUT_FORMAT" != "html" ]]; then
    echo -e "${RED}Error: Output format must be 'text', 'json', or 'html'.${RESET}"
    exit 1
  fi
  
  # Validate JSON output file is provided if JSON format is selected
  if [[ "$OUTPUT_FORMAT" == "json" && -z "$JSON_OUTPUT_FILE" ]]; then
    echo -e "${YELLOW}Warning: JSON output file not specified. Will print to stdout.${RESET}"
  fi
  
  # Validate Jira parameters if Jira is used
  if [[ -n "$JIRA_URL" && ( -z "$JIRA_USER" || -z "$JIRA_API_TOKEN" || -z "$JIRA_PROJECT" ) ]]; then
    echo -e "${RED}Error: Jira URL, user, API token, and project are all required for Jira integration.${RESET}"
    exit 1
  fi
  
  echo -e "${BLUE}Using parameters:${RESET}"
  echo -e "  AWS Region:          ${REGION}"
  echo -e "  AWS Profile:         ${PROFILE}"
  echo -e "  Warning Threshold:   ${WARNING_DAYS} days"
  echo -e "  Critical Threshold:  ${CRITICAL_DAYS} days"
  echo -e "  Check ACM:           ${CHECK_ACM}"
  echo -e "  Check Secrets:       ${CHECK_SECRETS}"
  echo -e "  Check SSH Keys:      ${CHECK_SSH_KEYS}"
  echo -e "  Output Format:       ${OUTPUT_FORMAT}"
  if [[ -n "$JSON_OUTPUT_FILE" ]]; then
    echo -e "  JSON Output File:    ${JSON_OUTPUT_FILE}"
  fi
  if [[ -n "$SLACK_WEBHOOK" ]]; then
    echo -e "  Slack Notifications: Enabled"
  fi
  if [[ -n "$SNS_TOPIC" ]]; then
    echo -e "  SNS Notifications:   Enabled"
  fi
  if [[ -n "$EMAIL" ]]; then
    echo -e "  Email Notifications: Enabled"
  fi
  if [[ -n "$JIRA_URL" ]]; then
    echo -e "  Jira Integration:    Enabled"
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

# Function to calculate days until expiration
function days_until_expiration {
  local EXPIRY_DATE="$1"
  
  # Handle different date formats
  if [[ "$EXPIRY_DATE" == *"T"* ]]; then
    # ISO format with T
    EXPIRY_SECONDS=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$(echo "$EXPIRY_DATE" | cut -d. -f1)" +%s 2>/dev/null || date -d "$(echo "$EXPIRY_DATE" | cut -d. -f1)" +%s)
  else
    # Other formats
    EXPIRY_SECONDS=$(date -j -f "%Y-%m-%d %H:%M:%S" "$EXPIRY_DATE" +%s 2>/dev/null || date -d "$EXPIRY_DATE" +%s)
  fi
  
  NOW_SECONDS=$(date +%s)
  DAYS_REMAINING=$(( ($EXPIRY_SECONDS - $NOW_SECONDS) / 86400 ))
  
  echo "$DAYS_REMAINING"
}

# Function to check status based on days remaining
function check_status {
  local DAYS="$1"
  
  if [[ "$DAYS" -le "$CRITICAL_DAYS" ]]; then
    echo "CRITICAL"
  elif [[ "$DAYS" -le "$WARNING_DAYS" ]]; then
    echo "WARNING"
  else
    echo "OK"
  fi
}

# Function to get status color
function status_color {
  local STATUS="$1"
  
  if [[ "$STATUS" == "CRITICAL" ]]; then
    echo "${RED}"
  elif [[ "$STATUS" == "WARNING" ]]; then
    echo "${YELLOW}"
  else
    echo "${GREEN}"
  fi
}

# Function to check ACM certificates
function check_acm_certificates {
  if [[ "$CHECK_ACM" != "true" ]]; then
    return
  fi
  
  echo -e "${BLUE}Checking ACM certificates...${RESET}"
  
  # Initialize results array
  ACM_RESULTS=()
  
  # List all certificates in ACM
  CERTS=$(aws acm list-certificates \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "CertificateSummaryList[*].[CertificateArn, DomainName]" \
    --output json)
  
  # Check if we found any certificates
  if [[ $(echo "$CERTS" | jq 'length') -eq 0 ]]; then
    echo -e "${YELLOW}⚠ No certificates found in ACM.${RESET}"
    return
  fi
  
  # Process each certificate
  for i in $(seq 0 $(echo "$CERTS" | jq 'length - 1')); do
    ARN=$(echo "$CERTS" | jq -r ".[$i][0]")
    DOMAIN=$(echo "$CERTS" | jq -r ".[$i][1]")
    
    # Get certificate details
    CERT_DETAILS=$(aws acm describe-certificate \
      --certificate-arn "$ARN" \
      --region "$REGION" \
      --profile "$PROFILE" \
      --query "Certificate.[Status, NotAfter, Subject, Type]" \
      --output json)
    
    STATUS=$(echo "$CERT_DETAILS" | jq -r ".[0]")
    EXPIRY_DATE=$(echo "$CERT_DETAILS" | jq -r ".[1]")
    SUBJECT=$(echo "$CERT_DETAILS" | jq -r ".[2]")
    TYPE=$(echo "$CERT_DETAILS" | jq -r ".[3]")
    
    # Skip certificates that are not ISSUED
    if [[ "$STATUS" != "ISSUED" ]]; then
      continue
    fi
    
    # Calculate days until expiration
    if [[ -n "$EXPIRY_DATE" && "$EXPIRY_DATE" != "null" ]]; then
      DAYS_REMAINING=$(days_until_expiration "$EXPIRY_DATE")
      CERT_STATUS=$(check_status "$DAYS_REMAINING")
      
      # Add to results array
      ACM_RESULTS+=("${DOMAIN}|${ARN}|${EXPIRY_DATE}|${DAYS_REMAINING}|${CERT_STATUS}|${TYPE}")
    else
      # For certificates without expiration (AWS managed)
      ACM_RESULTS+=("${DOMAIN}|${ARN}|N/A|N/A|OK|${TYPE}")
    fi
  done
  
  # Output results
  echo -e "${GREEN}✓ Found ${#ACM_RESULTS[@]} ACM certificates${RESET}"
}

# Function to check certificates in Secrets Manager
function check_secrets_manager {
  if [[ "$CHECK_SECRETS" != "true" ]]; then
    return
  fi
  
  echo -e "${BLUE}Checking certificates in Secrets Manager...${RESET}"
  
  # Initialize results array
  SECRETS_RESULTS=()
  
  # List all secrets
  SECRETS=$(aws secretsmanager list-secrets \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "SecretList[*].[ARN, Name, Tags]" \
    --output json)
  
  # Check if we found any secrets
  if [[ $(echo "$SECRETS" | jq 'length') -eq 0 ]]; then
    echo -e "${YELLOW}⚠ No secrets found in Secrets Manager.${RESET}"
    return
  fi
  
  # Process each secret
  for i in $(seq 0 $(echo "$SECRETS" | jq 'length - 1')); do
    ARN=$(echo "$SECRETS" | jq -r ".[$i][0]")
    NAME=$(echo "$SECRETS" | jq -r ".[$i][1]")
    TAGS=$(echo "$SECRETS" | jq -r ".[$i][2]")
    
    # Skip secrets that don't appear to be certificates
    if [[ ! "$NAME" == *"cert"* && ! "$NAME" == *"tls"* && ! "$NAME" == *"ssl"* ]]; then
      # Check tags for certificate indicators
      if [[ -z $(echo "$TAGS" | jq '.[] | select((.Key | test("(?i)cert|tls|ssl")) or (.Value | test("(?i)cert|tls|ssl")))') ]]; then
        continue
      fi
    fi
    
    # Get secret value
    SECRET_VALUE=$(aws secretsmanager get-secret-value \
      --secret-id "$ARN" \
      --region "$REGION" \
      --profile "$PROFILE" \
      --query "SecretString" \
      --output text)
    
    # Check if it's JSON
    if echo "$SECRET_VALUE" | jq -e . >/dev/null 2>&1; then
      # Check for expiry date in JSON
      EXPIRY_DATE=$(echo "$SECRET_VALUE" | jq -r '.expiry // .expiration // .expire_date // .not_after // .notAfter // empty')
      
      if [[ -z "$EXPIRY_DATE" || "$EXPIRY_DATE" == "null" ]]; then
        # Check for a certificate in PEM format
        if [[ "$SECRET_VALUE" == *"CERTIFICATE"* ]]; then
          # Extract certificate to check expiry
          TMP_CERT=$(mktemp)
          echo "$SECRET_VALUE" | jq -r '.["tls.crt"] // .certificate // .cert // empty' > "$TMP_CERT"
          
          # If empty, try to extract the whole secret if it looks like a certificate
          if [[ ! -s "$TMP_CERT" ]]; then
            if [[ "$SECRET_VALUE" == *"BEGIN CERTIFICATE"* ]]; then
              echo "$SECRET_VALUE" > "$TMP_CERT"
            fi
          fi
          
          # Check certificate expiration
          if [[ -s "$TMP_CERT" ]]; then
            EXPIRY_DATE=$(openssl x509 -in "$TMP_CERT" -noout -enddate 2>/dev/null | sed 's/notAfter=//')
            rm "$TMP_CERT"
          fi
        fi
      fi
      
      # If we have an expiry date, calculate days remaining
      if [[ -n "$EXPIRY_DATE" && "$EXPIRY_DATE" != "null" ]]; then
        DAYS_REMAINING=$(days_until_expiration "$EXPIRY_DATE")
        SECRET_STATUS=$(check_status "$DAYS_REMAINING")
        
        # Extract domain name if available
        DOMAIN=$(echo "$SECRET_VALUE" | jq -r '.domain // empty')
        if [[ -z "$DOMAIN" ]]; then
          DOMAIN=$(basename "$NAME")
        fi
        
        # Add to results array
        SECRETS_RESULTS+=("${DOMAIN}|${ARN}|${EXPIRY_DATE}|${DAYS_REMAINING}|${SECRET_STATUS}|Secret")
      fi
    elif [[ "$SECRET_VALUE" == *"CERTIFICATE"* ]]; then
      # Non-JSON certificate value
      TMP_CERT=$(mktemp)
      echo "$SECRET_VALUE" > "$TMP_CERT"
      
      # Check certificate expiration
      EXPIRY_DATE=$(openssl x509 -in "$TMP_CERT" -noout -enddate 2>/dev/null | sed 's/notAfter=//')
      rm "$TMP_CERT"
      
      if [[ -n "$EXPIRY_DATE" ]]; then
        DAYS_REMAINING=$(days_until_expiration "$EXPIRY_DATE")
        SECRET_STATUS=$(check_status "$DAYS_REMAINING")
        
        # Add to results array
        SECRETS_RESULTS+=("$(basename "$NAME")|${ARN}|${EXPIRY_DATE}|${DAYS_REMAINING}|${SECRET_STATUS}|Secret")
      fi
    fi
  done
  
  # Output results
  echo -e "${GREEN}✓ Found ${#SECRETS_RESULTS[@]} certificate secrets${RESET}"
}

# Function to check SSH keys in Secrets Manager
function check_ssh_keys {
  if [[ "$CHECK_SSH_KEYS" != "true" ]]; then
    return
  fi
  
  echo -e "${BLUE}Checking SSH keys in Secrets Manager...${RESET}"
  
  # Initialize results array
  SSH_RESULTS=()
  
  # List all secrets
  SECRETS=$(aws secretsmanager list-secrets \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "SecretList[*].[ARN, Name, Tags]" \
    --output json)
  
  # Check if we found any secrets
  if [[ $(echo "$SECRETS" | jq 'length') -eq 0 ]]; then
    echo -e "${YELLOW}⚠ No secrets found in Secrets Manager.${RESET}"
    return
  fi
  
  # Process each secret
  for i in $(seq 0 $(echo "$SECRETS" | jq 'length - 1')); do
    ARN=$(echo "$SECRETS" | jq -r ".[$i][0]")
    NAME=$(echo "$SECRETS" | jq -r ".[$i][1]")
    TAGS=$(echo "$SECRETS" | jq -r ".[$i][2]")
    
    # Skip secrets that don't appear to be SSH keys
    if [[ ! "$NAME" == *"ssh"* && ! "$NAME" == *"key"* ]]; then
      # Check tags for SSH key indicators
      if [[ -z $(echo "$TAGS" | jq '.[] | select((.Key | test("(?i)ssh|key")) or (.Value | test("(?i)ssh|key")))') ]]; then
        continue
      fi
    fi
    
    # Get secret value
    SECRET_VALUE=$(aws secretsmanager get-secret-value \
      --secret-id "$ARN" \
      --region "$REGION" \
      --profile "$PROFILE" \
      --query "SecretString" \
      --output text)
    
    # Check if it's JSON
    if echo "$SECRET_VALUE" | jq -e . >/dev/null 2>&1; then
      # Check for created_at or updated_at in JSON
      CREATED_DATE=$(echo "$SECRET_VALUE" | jq -r '.created_at // .updated_at // empty')
      
      if [[ -n "$CREATED_DATE" && "$CREATED_DATE" != "null" ]]; then
        # Calculate days since creation
        DAYS_AGE=$(days_until_expiration "$CREATED_DATE")
        DAYS_AGE=$((-DAYS_AGE))  # Convert to positive number
        
        # For SSH keys, we're not really checking expiration but age
        # We'll use the same thresholds but in days since creation
        if [[ "$DAYS_AGE" -gt "$WARNING_DAYS" ]]; then
          SSH_STATUS="WARNING"
        elif [[ "$DAYS_AGE" -gt "$CRITICAL_DAYS" ]]; then
          SSH_STATUS="CRITICAL"
        else
          SSH_STATUS="OK"
        fi
        
        # Extract key information
        KEY_NAME=$(echo "$SECRET_VALUE" | jq -r '.key_name // empty')
        if [[ -z "$KEY_NAME" ]]; then
          KEY_NAME=$(basename "$NAME")
        fi
        
        KEY_TYPE=$(echo "$SECRET_VALUE" | jq -r '.key_type // "ssh-key"')
        
        # Add to results array
        SSH_RESULTS+=("${KEY_NAME}|${ARN}|${CREATED_DATE}|${DAYS_AGE}|${SSH_STATUS}|${KEY_TYPE}")
      elif echo "$SECRET_VALUE" | jq -r '.private_key // empty' | grep -q "PRIVATE KEY"; then
        # It has a private key but no creation date
        # Add with unknown age
        KEY_NAME=$(echo "$SECRET_VALUE" | jq -r '.key_name // empty')
        if [[ -z "$KEY_NAME" ]]; then
          KEY_NAME=$(basename "$NAME")
        fi
        
        KEY_TYPE=$(echo "$SECRET_VALUE" | jq -r '.key_type // "ssh-key"')
        
        # Add to results array with unknown age but mark as warning due to missing metadata
        SSH_RESULTS+=("${KEY_NAME}|${ARN}|Unknown|Unknown|WARNING|${KEY_TYPE}")
      fi
    elif [[ "$SECRET_VALUE" == *"PRIVATE KEY"* ]]; then
      # Non-JSON private key value
      # Add with unknown age
      SSH_RESULTS+=("$(basename "$NAME")|${ARN}|Unknown|Unknown|WARNING|ssh-key")
    fi
  done
  
  # Output results
  echo -e "${GREEN}✓ Found ${#SSH_RESULTS[@]} SSH key secrets${RESET}"
}

# Function to display results in text format
function display_text_results {
  # Display ACM certificates
  if [[ "$CHECK_ACM" == "true" && ${#ACM_RESULTS[@]} -gt 0 ]]; then
    echo
    echo -e "${BOLD}ACM Certificates:${RESET}"
    printf "%-40s %-20s %-30s %-15s %-10s\n" "Domain" "Expires" "Days Remaining" "Status" "Type"
    echo "--------------------------------------------------------------------------------------------------------"
    
    for RESULT in "${ACM_RESULTS[@]}"; do
      IFS="|" read -r DOMAIN ARN EXPIRY DAYS STATUS TYPE <<< "$RESULT"
      STATUS_COL=$(status_color "$STATUS")
      printf "%-40s %-20s %-30s ${STATUS_COL}%-15s${RESET} %-10s\n" "$DOMAIN" "$EXPIRY" "$DAYS" "$STATUS" "$TYPE"
    done
  fi
  
  # Display Secrets Manager certificates
  if [[ "$CHECK_SECRETS" == "true" && ${#SECRETS_RESULTS[@]} -gt 0 ]]; then
    echo
    echo -e "${BOLD}Secrets Manager Certificates:${RESET}"
    printf "%-40s %-20s %-30s %-15s %-10s\n" "Name" "Expires" "Days Remaining" "Status" "Type"
    echo "--------------------------------------------------------------------------------------------------------"
    
    for RESULT in "${SECRETS_RESULTS[@]}"; do
      IFS="|" read -r NAME ARN EXPIRY DAYS STATUS TYPE <<< "$RESULT"
      STATUS_COL=$(status_color "$STATUS")
      printf "%-40s %-20s %-30s ${STATUS_COL}%-15s${RESET} %-10s\n" "$NAME" "$EXPIRY" "$DAYS" "$STATUS" "$TYPE"
    done
  fi
  
  # Display SSH keys
  if [[ "$CHECK_SSH_KEYS" == "true" && ${#SSH_RESULTS[@]} -gt 0 ]]; then
    echo
    echo -e "${BOLD}SSH Keys:${RESET}"
    printf "%-40s %-20s %-30s %-15s %-10s\n" "Name" "Created" "Days Old" "Status" "Type"
    echo "--------------------------------------------------------------------------------------------------------"
    
    for RESULT in "${SSH_RESULTS[@]}"; do
      IFS="|" read -r NAME ARN CREATED DAYS STATUS TYPE <<< "$RESULT"
      STATUS_COL=$(status_color "$STATUS")
      printf "%-40s %-20s %-30s ${STATUS_COL}%-15s${RESET} %-10s\n" "$NAME" "$CREATED" "$DAYS" "$STATUS" "$TYPE"
    done
  fi
  
  # Display summary
  echo
  echo -e "${BOLD}Summary:${RESET}"
  echo -e "Total ACM certificates: ${#ACM_RESULTS[@]}"
  echo -e "Total certificate secrets: ${#SECRETS_RESULTS[@]}"
  echo -e "Total SSH keys: ${#SSH_RESULTS[@]}"
  
  # Count warnings and criticals
  WARNING_COUNT=0
  CRITICAL_COUNT=0
  
  for RESULT in "${ACM_RESULTS[@]}" "${SECRETS_RESULTS[@]}" "${SSH_RESULTS[@]}"; do
    IFS="|" read -r _ _ _ _ STATUS _ <<< "$RESULT"
    if [[ "$STATUS" == "WARNING" ]]; then
      ((WARNING_COUNT++))
    elif [[ "$STATUS" == "CRITICAL" ]]; then
      ((CRITICAL_COUNT++))
    fi
  done
  
  echo -e "${YELLOW}Warning: ${WARNING_COUNT}${RESET}"
  echo -e "${RED}Critical: ${CRITICAL_COUNT}${RESET}"
}

# Function to generate JSON output
function generate_json_output {
  # Create JSON structure
  JSON=$(cat <<EOF
{
  "scan_date": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "region": "${REGION}",
  "warning_threshold": ${WARNING_DAYS},
  "critical_threshold": ${CRITICAL_DAYS},
  "acm_certificates": [
EOF
)

  # Add ACM certificates
  for i in "${!ACM_RESULTS[@]}"; do
    IFS="|" read -r DOMAIN ARN EXPIRY DAYS STATUS TYPE <<< "${ACM_RESULTS[$i]}"
    JSON+=$(cat <<EOF
    {
      "domain": "${DOMAIN}",
      "arn": "${ARN}",
      "expiry": "${EXPIRY}",
      "days_remaining": "${DAYS}",
      "status": "${STATUS}",
      "type": "${TYPE}"
    }$(if [[ $i -lt $((${#ACM_RESULTS[@]} - 1)) ]]; then echo ","; fi)
EOF
)
  done

  JSON+=$(cat <<EOF
  ],
  "certificate_secrets": [
EOF
)

  # Add Secrets Manager certificates
  for i in "${!SECRETS_RESULTS[@]}"; do
    IFS="|" read -r NAME ARN EXPIRY DAYS STATUS TYPE <<< "${SECRETS_RESULTS[$i]}"
    JSON+=$(cat <<EOF
    {
      "name": "${NAME}",
      "arn": "${ARN}",
      "expiry": "${EXPIRY}",
      "days_remaining": "${DAYS}",
      "status": "${STATUS}",
      "type": "${TYPE}"
    }$(if [[ $i -lt $((${#SECRETS_RESULTS[@]} - 1)) ]]; then echo ","; fi)
EOF
)
  done

  JSON+=$(cat <<EOF
  ],
  "ssh_keys": [
EOF
)

  # Add SSH keys
  for i in "${!SSH_RESULTS[@]}"; do
    IFS="|" read -r NAME ARN CREATED DAYS STATUS TYPE <<< "${SSH_RESULTS[$i]}"
    JSON+=$(cat <<EOF
    {
      "name": "${NAME}",
      "arn": "${ARN}",
      "created": "${CREATED}",
      "days_age": "${DAYS}",
      "status": "${STATUS}",
      "type": "${TYPE}"
    }$(if [[ $i -lt $((${#SSH_RESULTS[@]} - 1)) ]]; then echo ","; fi)
EOF
)
  done

  # Count warnings and criticals
  WARNING_COUNT=0
  CRITICAL_COUNT=0
  
  for RESULT in "${ACM_RESULTS[@]}" "${SECRETS_RESULTS[@]}" "${SSH_RESULTS[@]}"; do
    IFS="|" read -r _ _ _ _ STATUS _ <<< "$RESULT"
    if [[ "$STATUS" == "WARNING" ]]; then
      ((WARNING_COUNT++))
    elif [[ "$STATUS" == "CRITICAL" ]]; then
      ((CRITICAL_COUNT++))
    fi
  done

  JSON+=$(cat <<EOF
  ],
  "summary": {
    "total_acm_certificates": ${#ACM_RESULTS[@]},
    "total_certificate_secrets": ${#SECRETS_RESULTS[@]},
    "total_ssh_keys": ${#SSH_RESULTS[@]},
    "warning_count": ${WARNING_COUNT},
    "critical_count": ${CRITICAL_COUNT}
  }
}
EOF
)

  # Output JSON
  if [[ -n "$JSON_OUTPUT_FILE" ]]; then
    echo "$JSON" | jq . > "$JSON_OUTPUT_FILE"
    echo -e "${GREEN}✓ JSON output written to ${JSON_OUTPUT_FILE}${RESET}"
  else
    echo "$JSON" | jq .
  fi
}

# Function to generate HTML output
function generate_html_output {
  # Create HTML structure
  HTML=$(cat <<EOF
<!DOCTYPE html>
<html>
<head>
  <title>Certificate Monitoring Report</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 20px; }
    h1 { color: #333; }
    h2 { color: #666; margin-top: 30px; }
    table { border-collapse: collapse; width: 100%; margin-top: 10px; }
    th, td { text-align: left; padding: 8px; border-bottom: 1px solid #ddd; }
    th { background-color: #f2f2f2; }
    tr:hover { background-color: #f5f5f5; }
    .ok { color: green; }
    .warning { color: orange; }
    .critical { color: red; }
    .summary { margin-top: 30px; }
  </style>
</head>
<body>
  <h1>Certificate Monitoring Report</h1>
  <p>Scan Date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")</p>
  <p>Region: ${REGION}</p>
  <p>Warning Threshold: ${WARNING_DAYS} days</p>
  <p>Critical Threshold: ${CRITICAL_DAYS} days</p>
EOF
)

  # Add ACM certificates
  if [[ "$CHECK_ACM" == "true" && ${#ACM_RESULTS[@]} -gt 0 ]]; then
    HTML+=$(cat <<EOF
  <h2>ACM Certificates</h2>
  <table>
    <tr>
      <th>Domain</th>
      <th>Expires</th>
      <th>Days Remaining</th>
      <th>Status</th>
      <th>Type</th>
    </tr>
EOF
)

    for RESULT in "${ACM_RESULTS[@]}"; do
      IFS="|" read -r DOMAIN ARN EXPIRY DAYS STATUS TYPE <<< "$RESULT"
      HTML+=$(cat <<EOF
    <tr>
      <td>${DOMAIN}</td>
      <td>${EXPIRY}</td>
      <td>${DAYS}</td>
      <td class="$(echo "${STATUS}" | tr '[:upper:]' '[:lower:]')">${STATUS}</td>
      <td>${TYPE}</td>
    </tr>
EOF
)
    done

    HTML+="  </table>"
  fi

  # Add Secrets Manager certificates
  if [[ "$CHECK_SECRETS" == "true" && ${#SECRETS_RESULTS[@]} -gt 0 ]]; then
    HTML+=$(cat <<EOF
  <h2>Secrets Manager Certificates</h2>
  <table>
    <tr>
      <th>Name</th>
      <th>Expires</th>
      <th>Days Remaining</th>
      <th>Status</th>
      <th>Type</th>
    </tr>
EOF
)

    for RESULT in "${SECRETS_RESULTS[@]}"; do
      IFS="|" read -r NAME ARN EXPIRY DAYS STATUS TYPE <<< "$RESULT"
      HTML+=$(cat <<EOF
    <tr>
      <td>${NAME}</td>
      <td>${EXPIRY}</td>
      <td>${DAYS}</td>
      <td class="$(echo "${STATUS}" | tr '[:upper:]' '[:lower:]')">${STATUS}</td>
      <td>${TYPE}</td>
    </tr>
EOF
)
    done

    HTML+="  </table>"
  fi

  # Add SSH keys
  if [[ "$CHECK_SSH_KEYS" == "true" && ${#SSH_RESULTS[@]} -gt 0 ]]; then
    HTML+=$(cat <<EOF
  <h2>SSH Keys</h2>
  <table>
    <tr>
      <th>Name</th>
      <th>Created</th>
      <th>Days Old</th>
      <th>Status</th>
      <th>Type</th>
    </tr>
EOF
)

    for RESULT in "${SSH_RESULTS[@]}"; do
      IFS="|" read -r NAME ARN CREATED DAYS STATUS TYPE <<< "$RESULT"
      HTML+=$(cat <<EOF
    <tr>
      <td>${NAME}</td>
      <td>${CREATED}</td>
      <td>${DAYS}</td>
      <td class="$(echo "${STATUS}" | tr '[:upper:]' '[:lower:]')">${STATUS}</td>
      <td>${TYPE}</td>
    </tr>
EOF
)
    done

    HTML+="  </table>"
  fi

  # Count warnings and criticals
  WARNING_COUNT=0
  CRITICAL_COUNT=0
  
  for RESULT in "${ACM_RESULTS[@]}" "${SECRETS_RESULTS[@]}" "${SSH_RESULTS[@]}"; do
    IFS="|" read -r _ _ _ _ STATUS _ <<< "$RESULT"
    if [[ "$STATUS" == "WARNING" ]]; then
      ((WARNING_COUNT++))
    elif [[ "$STATUS" == "CRITICAL" ]]; then
      ((CRITICAL_COUNT++))
    fi
  done

  # Add summary
  HTML+=$(cat <<EOF
  <div class="summary">
    <h2>Summary</h2>
    <p>Total ACM certificates: ${#ACM_RESULTS[@]}</p>
    <p>Total certificate secrets: ${#SECRETS_RESULTS[@]}</p>
    <p>Total SSH keys: ${#SSH_RESULTS[@]}</p>
    <p class="warning">Warning: ${WARNING_COUNT}</p>
    <p class="critical">Critical: ${CRITICAL_COUNT}</p>
  </div>
</body>
</html>
EOF
)

  # Output HTML
  if [[ -n "$JSON_OUTPUT_FILE" ]]; then
    # Replace .json with .html if the output file has a .json extension
    HTML_FILE="${JSON_OUTPUT_FILE%.json}.html"
    echo "$HTML" > "$HTML_FILE"
    echo -e "${GREEN}✓ HTML output written to ${HTML_FILE}${RESET}"
  else
    echo "$HTML"
  fi
}

# Function to send notifications
function send_notifications {
  # Only send notifications if there are warnings or criticals
  WARNING_COUNT=0
  CRITICAL_COUNT=0
  
  for RESULT in "${ACM_RESULTS[@]}" "${SECRETS_RESULTS[@]}" "${SSH_RESULTS[@]}"; do
    IFS="|" read -r _ _ _ _ STATUS _ <<< "$RESULT"
    if [[ "$STATUS" == "WARNING" ]]; then
      ((WARNING_COUNT++))
    elif [[ "$STATUS" == "CRITICAL" ]]; then
      ((CRITICAL_COUNT++))
    fi
  done
  
  if [[ "$WARNING_COUNT" -eq 0 && "$CRITICAL_COUNT" -eq 0 ]]; then
    echo -e "${GREEN}✓ No warnings or criticals found. Skipping notifications.${RESET}"
    return
  fi
  
  # Prepare notification message
  NOTIFICATION_SUBJECT="[${REGION}] Certificate Monitoring: ${CRITICAL_COUNT} critical, ${WARNING_COUNT} warning"
  
  # Send to Slack
  if [[ -n "$SLACK_WEBHOOK" ]]; then
    echo -e "${BLUE}Sending Slack notification...${RESET}"
    
    # Create Slack message
    SLACK_MESSAGE=$(cat <<EOF
{
  "text": "*${NOTIFICATION_SUBJECT}*",
  "blocks": [
    {
      "type": "header",
      "text": {
        "type": "plain_text",
        "text": "Certificate Monitoring Report"
      }
    },
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "*Region:* ${REGION}\n*Scan Date:* $(date -u +"%Y-%m-%d %H:%M:%S UTC")\n*Warning Threshold:* ${WARNING_DAYS} days\n*Critical Threshold:* ${CRITICAL_DAYS} days"
      }
    },
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "*Summary:*\n• Total ACM certificates: ${#ACM_RESULTS[@]}\n• Total certificate secrets: ${#SECRETS_RESULTS[@]}\n• Total SSH keys: ${#SSH_RESULTS[@]}\n• :warning: Warning: ${WARNING_COUNT}\n• :rotating_light: Critical: ${CRITICAL_COUNT}"
      }
    }
EOF
)

    # Add critical certificates
    if [[ "$CRITICAL_COUNT" -gt 0 ]]; then
      SLACK_MESSAGE+=$(cat <<EOF
,
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "*Critical Certificates:*"
      }
    },
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "
EOF
)

      for RESULT in "${ACM_RESULTS[@]}" "${SECRETS_RESULTS[@]}" "${SSH_RESULTS[@]}"; do
        IFS="|" read -r NAME ARN EXPIRY DAYS STATUS TYPE <<< "$RESULT"
        if [[ "$STATUS" == "CRITICAL" ]]; then
          SLACK_MESSAGE+="• *${NAME}* (${TYPE}): ${EXPIRY} (${DAYS} days)\n"
        fi
      done

      SLACK_MESSAGE+="\"
      }
    }"
    fi

    # Add warning certificates
    if [[ "$WARNING_COUNT" -gt 0 ]]; then
      SLACK_MESSAGE+=$(cat <<EOF
,
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "*Warning Certificates:*"
      }
    },
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "
EOF
)

      for RESULT in "${ACM_RESULTS[@]}" "${SECRETS_RESULTS[@]}" "${SSH_RESULTS[@]}"; do
        IFS="|" read -r NAME ARN EXPIRY DAYS STATUS TYPE <<< "$RESULT"
        if [[ "$STATUS" == "WARNING" ]]; then
          SLACK_MESSAGE+="• *${NAME}* (${TYPE}): ${EXPIRY} (${DAYS} days)\n"
        fi
      done

      SLACK_MESSAGE+="\"
      }
    }"
    fi

    # Close the JSON
    SLACK_MESSAGE+="
  ]
}"

    # Send to Slack
    if curl -s -X POST -H 'Content-type: application/json' --data "$SLACK_MESSAGE" "$SLACK_WEBHOOK" &>/dev/null; then
      echo -e "${GREEN}✓ Slack notification sent${RESET}"
    else
      echo -e "${RED}✘ Failed to send Slack notification${RESET}"
    fi
  fi
  
  # Send to SNS
  if [[ -n "$SNS_TOPIC" ]]; then
    echo -e "${BLUE}Sending SNS notification...${RESET}"
    
    # Create SNS message
    SNS_MESSAGE=$(cat <<EOF
Certificate Monitoring Report

Region: ${REGION}
Scan Date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Warning Threshold: ${WARNING_DAYS} days
Critical Threshold: ${CRITICAL_DAYS} days

Summary:
- Total ACM certificates: ${#ACM_RESULTS[@]}
- Total certificate secrets: ${#SECRETS_RESULTS[@]}
- Total SSH keys: ${#SSH_RESULTS[@]}
- Warning: ${WARNING_COUNT}
- Critical: ${CRITICAL_COUNT}

EOF
)

    # Add critical certificates
    if [[ "$CRITICAL_COUNT" -gt 0 ]]; then
      SNS_MESSAGE+="Critical Certificates:\n"
      
      for RESULT in "${ACM_RESULTS[@]}" "${SECRETS_RESULTS[@]}" "${SSH_RESULTS[@]}"; do
        IFS="|" read -r NAME ARN EXPIRY DAYS STATUS TYPE <<< "$RESULT"
        if [[ "$STATUS" == "CRITICAL" ]]; then
          SNS_MESSAGE+="- ${NAME} (${TYPE}): ${EXPIRY} (${DAYS} days)\n"
        fi
      done
      
      SNS_MESSAGE+="\n"
    fi
    
    # Add warning certificates
    if [[ "$WARNING_COUNT" -gt 0 ]]; then
      SNS_MESSAGE+="Warning Certificates:\n"
      
      for RESULT in "${ACM_RESULTS[@]}" "${SECRETS_RESULTS[@]}" "${SSH_RESULTS[@]}"; do
        IFS="|" read -r NAME ARN EXPIRY DAYS STATUS TYPE <<< "$RESULT"
        if [[ "$STATUS" == "WARNING" ]]; then
          SNS_MESSAGE+="- ${NAME} (${TYPE}): ${EXPIRY} (${DAYS} days)\n"
        fi
      done
    fi
    
    # Send to SNS
    if aws sns publish \
      --topic-arn "$SNS_TOPIC" \
      --subject "$NOTIFICATION_SUBJECT" \
      --message "$SNS_MESSAGE" \
      --region "$REGION" \
      --profile "$PROFILE" &>/dev/null; then
      echo -e "${GREEN}✓ SNS notification sent${RESET}"
    else
      echo -e "${RED}✘ Failed to send SNS notification${RESET}"
    fi
  fi
  
  # Send to email (via SNS)
  if [[ -n "$EMAIL" ]]; then
    echo -e "${BLUE}Sending email notification...${RESET}"
    
    # Create a temporary SNS topic for email if email is provided but no SNS topic
    if [[ -z "$SNS_TOPIC" ]]; then
      echo -e "${BLUE}Creating temporary SNS topic for email...${RESET}"
      
      # Create SNS topic
      SNS_TOPIC_RESPONSE=$(aws sns create-topic \
        --name "certificate-monitor-temp-$(date +%s)" \
        --region "$REGION" \
        --profile "$PROFILE")
      
      TEMP_SNS_TOPIC=$(echo "$SNS_TOPIC_RESPONSE" | jq -r '.TopicArn')
      
      # Subscribe email to topic
      aws sns subscribe \
        --topic-arn "$TEMP_SNS_TOPIC" \
        --protocol email \
        --notification-endpoint "$EMAIL" \
        --region "$REGION" \
        --profile "$PROFILE" &>/dev/null
      
      echo -e "${YELLOW}⚠ A confirmation email has been sent to ${EMAIL}. Please confirm the subscription.${RESET}"
      echo -e "${YELLOW}⚠ Email notification will only be sent after confirmation.${RESET}"
      
      # Set SNS topic for sending
      SNS_TOPIC="$TEMP_SNS_TOPIC"
      
      # Wait for confirmation (5 minutes max)
      echo -e "${BLUE}Waiting for email confirmation (press Ctrl+C to skip)...${RESET}"
      for i in {1..30}; do
        sleep 10
        
        # Check if subscription is confirmed
        SUBSCRIPTION_RESPONSE=$(aws sns list-subscriptions-by-topic \
          --topic-arn "$TEMP_SNS_TOPIC" \
          --region "$REGION" \
          --profile "$PROFILE")
        
        SUBSCRIPTION_STATUS=$(echo "$SUBSCRIPTION_RESPONSE" | jq -r '.Subscriptions[0].SubscriptionArn')
        
        if [[ "$SUBSCRIPTION_STATUS" != "PendingConfirmation" ]]; then
          echo -e "${GREEN}✓ Email subscription confirmed${RESET}"
          break
        fi
        
        echo -n "."
      done
      
      echo
    fi
    
    # Create email message (same as SNS message)
    EMAIL_MESSAGE="$SNS_MESSAGE"
    
    # Send via SNS
    if aws sns publish \
      --topic-arn "$SNS_TOPIC" \
      --subject "$NOTIFICATION_SUBJECT" \
      --message "$EMAIL_MESSAGE" \
      --region "$REGION" \
      --profile "$PROFILE" &>/dev/null; then
      echo -e "${GREEN}✓ Email notification sent${RESET}"
    else
      echo -e "${RED}✘ Failed to send email notification${RESET}"
    fi
    
    # Clean up temporary SNS topic
    if [[ -n "$TEMP_SNS_TOPIC" ]]; then
      echo -e "${BLUE}Cleaning up temporary SNS topic...${RESET}"
      
      # Delete all subscriptions
      SUBSCRIPTION_RESPONSE=$(aws sns list-subscriptions-by-topic \
        --topic-arn "$TEMP_SNS_TOPIC" \
        --region "$REGION" \
        --profile "$PROFILE")
      
      SUBSCRIPTION_ARN=$(echo "$SUBSCRIPTION_RESPONSE" | jq -r '.Subscriptions[0].SubscriptionArn')
      
      if [[ "$SUBSCRIPTION_ARN" != "PendingConfirmation" ]]; then
        aws sns unsubscribe \
          --subscription-arn "$SUBSCRIPTION_ARN" \
          --region "$REGION" \
          --profile "$PROFILE" &>/dev/null
      fi
      
      # Delete topic
      aws sns delete-topic \
        --topic-arn "$TEMP_SNS_TOPIC" \
        --region "$REGION" \
        --profile "$PROFILE" &>/dev/null
      
      echo -e "${GREEN}✓ Temporary SNS topic cleaned up${RESET}"
    fi
  fi
  
  # Create Jira tickets
  if [[ -n "$JIRA_URL" && -n "$JIRA_USER" && -n "$JIRA_API_TOKEN" && -n "$JIRA_PROJECT" ]]; then
    echo -e "${BLUE}Creating Jira tickets for critical certificates...${RESET}"
    
    # Only create tickets for critical certificates
    for RESULT in "${ACM_RESULTS[@]}" "${SECRETS_RESULTS[@]}" "${SSH_RESULTS[@]}"; do
      IFS="|" read -r NAME ARN EXPIRY DAYS STATUS TYPE <<< "$RESULT"
      if [[ "$STATUS" == "CRITICAL" ]]; then
        # Create Jira ticket
        JIRA_ISSUE_DATA=$(cat <<EOF
{
  "fields": {
    "project": {
      "key": "${JIRA_PROJECT}"
    },
    "summary": "Certificate Expiring: ${NAME} (${DAYS} days)",
    "description": "Certificate/key is expiring soon and needs attention.\n\n*Details:*\n- Name: ${NAME}\n- Type: ${TYPE}\n- Expiration: ${EXPIRY}\n- Days Remaining: ${DAYS}\n- ARN: ${ARN}\n\nPlease take action to renew or rotate this certificate.",
    "issuetype": {
      "name": "Task"
    },
    "priority": {
      "name": "High"
    },
    "labels": ["certificate-expiry"]
  }
}
EOF
)
        
        # Send to Jira
        JIRA_RESPONSE=$(curl -s -X POST \
          -H "Content-Type: application/json" \
          -H "Accept: application/json" \
          -u "${JIRA_USER}:${JIRA_API_TOKEN}" \
          --data "$JIRA_ISSUE_DATA" \
          "${JIRA_URL}/rest/api/2/issue")
        
        JIRA_KEY=$(echo "$JIRA_RESPONSE" | jq -r '.key // empty')
        
        if [[ -n "$JIRA_KEY" ]]; then
          echo -e "${GREEN}✓ Created Jira ticket ${JIRA_KEY} for ${NAME}${RESET}"
        else
          echo -e "${RED}✘ Failed to create Jira ticket for ${NAME}${RESET}"
          echo -e "${RED}Response: $(echo "$JIRA_RESPONSE" | jq .)${RESET}"
        fi
      fi
    done
  fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  key="$1"

  case $key in
    -r|--region)
      REGION="$2"
      shift 2
      ;;
    -p|--profile)
      PROFILE="$2"
      shift 2
      ;;
    -w|--warning)
      WARNING_DAYS="$2"
      shift 2
      ;;
    -c|--critical)
      CRITICAL_DAYS="$2"
      shift 2
      ;;
    --no-acm)
      CHECK_ACM=false
      shift
      ;;
    --no-secrets)
      CHECK_SECRETS=false
      shift
      ;;
    --no-ssh)
      CHECK_SSH_KEYS=false
      shift
      ;;
    -o|--output)
      OUTPUT_FORMAT="$2"
      shift 2
      ;;
    -f|--file)
      JSON_OUTPUT_FILE="$2"
      shift 2
      ;;
    --slack)
      SLACK_WEBHOOK="$2"
      shift 2
      ;;
    --sns)
      SNS_TOPIC="$2"
      shift 2
      ;;
    --email)
      EMAIL="$2"
      shift 2
      ;;
    --jira)
      JIRA_URL="$2"
      JIRA_USER="$3"
      JIRA_API_TOKEN="$4"
      shift 4
      ;;
    --jira-project)
      JIRA_PROJECT="$2"
      shift 2
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
check_acm_certificates
check_secrets_manager
check_ssh_keys

# Display results in the requested format
if [[ "$OUTPUT_FORMAT" == "text" ]]; then
  display_text_results
elif [[ "$OUTPUT_FORMAT" == "json" ]]; then
  generate_json_output
elif [[ "$OUTPUT_FORMAT" == "html" ]]; then
  generate_html_output
fi

# Send notifications if configured
if [[ -n "$SLACK_WEBHOOK" || -n "$SNS_TOPIC" || -n "$EMAIL" || -n "$JIRA_URL" ]]; then
  send_notifications
fi

exit 0