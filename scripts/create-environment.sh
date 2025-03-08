#!/usr/bin/env bash
set -e

# Script to create a new environment using Copier templates

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Source utility functions
source "${SCRIPT_DIR}/utils.sh"

# Default configuration
TEMPLATE_TYPE="dev"
TENANT=""
ACCOUNT=""
ENVIRONMENT=""
VPC_CIDR=""
AWS_REGION="$(get_aws_region)"
EKS_ENABLED="true"
RDS_ENABLED="false"
TARGET_DIR=""
FORCE="false"
SHOW_ONLY="false"
TEMPLATE_DIR="$REPO_ROOT/templates/copier-environment"

# Load environment variables from .env file
load_env_file "$REPO_ROOT"

# Help message
show_help() {
  echo -e "${BOLD}Environment Creation Tool${RESET}"
  echo -e "Creates a new environment using Copier templates."
  echo
  echo -e "${BOLD}Usage:${RESET}"
  echo "  $0 [options]"
  echo
  echo -e "${BOLD}Options:${RESET}"
  echo "  -h, --help                Show this help message"
  echo "  -t, --env-type TYPE       Environment type (development, staging, production)"
  echo "  --tenant TENANT           Tenant name (required)"
  echo "  --account ACCOUNT         Account name (required)"
  echo "  --environment ENV_NAME    Environment name (required)"
  echo "  --vpc-cidr CIDR           VPC CIDR block (required)"
  echo "  --region REGION           AWS region (default: us-west-2)"
  echo "  --eks BOOLEAN             Enable EKS (default: true)"
  echo "  --rds BOOLEAN             Enable RDS (default: false)"
  echo "  --target-dir DIR          Target directory for the generated environment"
  echo "  --force                   Force overwrite of existing environment"
  echo "  --show-only               Show what would be generated without creating"
  echo
  echo -e "${BOLD}Environment Types:${RESET}"
  echo "  development - Development environment with minimal resources"
  echo "  staging     - Staging environment with moderate resources"
  echo "  production  - Production environment with high availability"
  echo
  echo -e "${BOLD}Examples:${RESET}"
  echo "  $0 --env-type development --tenant mycompany --account dev --environment test-01 --vpc-cidr 10.0.0.0/16"
  echo "  $0 -t production --tenant mycompany --account prod --environment prod-01 --vpc-cidr 10.0.0.0/16 --region us-east-1"
  echo "  $0 -t staging --tenant mycompany --account staging --environment stage-01 --vpc-cidr 10.0.0.0/16 --rds true"
  echo
}

# Validate inputs
validate_inputs() {
  # Check required parameters
  if [[ -z "$TENANT" ]]; then
    echo -e "${RED}Error: Tenant is required.${RESET}"
    show_help
    exit 1
  fi
  
  if [[ -z "$ACCOUNT" ]]; then
    echo -e "${RED}Error: Account is required.${RESET}"
    show_help
    exit 1
  fi
  
  if [[ -z "$ENVIRONMENT" ]]; then
    echo -e "${RED}Error: Environment name is required.${RESET}"
    show_help
    exit 1
  fi
  
  if [[ -z "$VPC_CIDR" ]]; then
    echo -e "${RED}Error: VPC CIDR block is required.${RESET}"
    show_help
    exit 1
  fi
  
  # Validate template directory
  if [[ ! -d "$TEMPLATE_DIR" ]]; then
    echo -e "${RED}Error: Template directory not found: $TEMPLATE_DIR${RESET}"
    exit 1
  fi
  
  # Validate environment type
  if [[ "$TEMPLATE_TYPE" != "development" && "$TEMPLATE_TYPE" != "staging" && "$TEMPLATE_TYPE" != "production" ]]; then
    echo -e "${RED}Error: Invalid environment type. Must be 'development', 'staging', or 'production'.${RESET}"
    exit 1
  fi
  
  # Validate CIDR format
  if ! validate_cidr "$VPC_CIDR"; then
    exit 1
  fi
  
  # Validate environment name format
  if ! validate_env_name "$ENVIRONMENT"; then
    exit 1
  fi
  
  # Set target directory if not provided
  if [[ -z "$TARGET_DIR" ]]; then
    TARGET_DIR="$REPO_ROOT/stacks/$TENANT/$ACCOUNT/$ENVIRONMENT"
  fi
  
  # Check if target directory exists and handle it
  if ! ensure_directory "$TARGET_DIR" "$FORCE"; then
    exit 1
  fi
}

# Create environment using Copier
create_environment() {
  echo -e "${BLUE}Creating environment using Copier template...${RESET}"
  echo -e "  Tenant: $TENANT"
  echo -e "  Account: $ACCOUNT"
  echo -e "  Environment: $ENVIRONMENT"
  echo -e "  Environment Type: $TEMPLATE_TYPE"
  echo -e "  VPC CIDR: $VPC_CIDR"
  echo -e "  AWS Region: $AWS_REGION"
  echo -e "  EKS Enabled: $EKS_ENABLED"
  echo -e "  RDS Enabled: $RDS_ENABLED"
  echo -e "  Target Directory: $TARGET_DIR"
  
  if [[ "$SHOW_ONLY" == "true" ]]; then
    echo -e "${YELLOW}Show-only mode, not creating environment.${RESET}"
    return
  fi
  
  # Check AWS CLI version
  check_aws_cli "2.0.0"
  
  # Verify Copier installation
  verify_copier_installation "$COPIER_VERSION"
  
  # Determine availability zones based on region
  local AVAILABILITY_ZONES=$(get_availability_zones "$AWS_REGION" 3)
  
  # Create temporary answers file with secure permissions
  local ANSWERS_FILE=$(create_secure_temp_file)
  
  cat > "$ANSWERS_FILE" << EOF
tenant: "$TENANT"
account: "$ACCOUNT"
env_name: "$ENVIRONMENT"
env_type: "$TEMPLATE_TYPE"
aws_region: "$AWS_REGION"
vpc_cidr: "$VPC_CIDR"
availability_zones: $AVAILABILITY_ZONES
eks_cluster: $EKS_ENABLED
rds_instances: $RDS_ENABLED
enable_logging: true
enable_monitoring: true
compliance_level: "basic"
team_email: "team@example.com"
create_date: "$(date +%Y-%m-%d)"
EOF

  # Create the environment directory if it doesn't exist
  mkdir -p "$TARGET_DIR"
  
  echo -e "${BLUE}Running Copier to generate environment...${RESET}"
  copier copy --answers-file "$ANSWERS_FILE" "$TEMPLATE_DIR" "$TARGET_DIR"
  
  # Clean up temporary file
  rm -f "$ANSWERS_FILE"
  
  echo -e "${GREEN}Environment created successfully at $TARGET_DIR${RESET}"
  echo -e "You can now deploy it using:"
  echo -e "  atmos terraform plan vpc -s $TENANT-$ACCOUNT-$ENVIRONMENT"
  echo -e "  atmos workflow apply-environment tenant=$TENANT account=$ACCOUNT environment=$ENVIRONMENT"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      show_help
      exit 0
      ;;
    -t|--env-type)
      TEMPLATE_TYPE="$2"
      shift 2
      ;;
    --tenant)
      TENANT="$2"
      shift 2
      ;;
    --account)
      ACCOUNT="$2"
      shift 2
      ;;
    --environment)
      ENVIRONMENT="$2"
      shift 2
      ;;
    --vpc-cidr)
      VPC_CIDR="$2"
      shift 2
      ;;
    --region)
      AWS_REGION="$2"
      shift 2
      ;;
    --eks)
      EKS_ENABLED="$2"
      shift 2
      ;;
    --rds)
      RDS_ENABLED="$2"
      shift 2
      ;;
    --target-dir)
      TARGET_DIR="$2"
      shift 2
      ;;
    --force)
      FORCE="true"
      shift
      ;;
    --show-only)
      SHOW_ONLY="true"
      shift
      ;;
    *)
      echo -e "${RED}Unknown option: $1${RESET}"
      show_help
      exit 1
      ;;
  esac
done

# Main execution
validate_inputs
create_environment