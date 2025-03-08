#!/bin/bash
set -eo pipefail

# Wrapper script for Atmos to provide better error handling and logging
# Usage: atmos-wrapper.sh [command] [args...]

# Log file locations
LOG_DIR="/atlantis/logs"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
LOG_FILE="${LOG_DIR}/atmos-${TIMESTAMP}.log"

# Create log directory if it doesn't exist
mkdir -p "${LOG_DIR}"

# Function to log messages
log() {
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] $1" | tee -a "${LOG_FILE}"
}

# Function to handle errors
handle_error() {
    log "ERROR: Command failed with exit code $1"
    log "See log file for details: ${LOG_FILE}"
    exit $1
}

# Parse command line arguments
if [ $# -lt 1 ]; then
    log "Usage: atmos-wrapper.sh [command] [args...]"
    log "Example: atmos-wrapper.sh terraform plan vpc -s tenant-account-environment"
    exit 1
fi

COMMAND="$1"
shift

# Check if component and stack are specified for terraform commands
if [[ "$COMMAND" == "terraform" ]]; then
    # For terraform commands, we need at least a subcommand and a component
    if [ $# -lt 2 ]; then
        log "For terraform commands, you must specify a subcommand and component"
        log "Example: atmos-wrapper.sh terraform plan vpc -s tenant-account-environment"
        exit 1
    fi
    
    SUBCOMMAND="$1"
    COMPONENT="$2"
    shift 2
    
    # Check if stack is specified
    STACK=""
    idx=0
    for i in "$@"; do
        if [[ "$i" == "-s" || "$i" == "--stack" ]]; then
            STACK_IDX=$((idx+1))
            if [ $STACK_IDX -lt $# ]; then
                # Use array element syntax correctly
                STACK="${@:$STACK_IDX:1}"
                break
            fi
        fi
        idx=$((idx+1))
    done
    
    if [[ -z "$STACK" ]]; then
        log "ERROR: Stack must be specified with -s or --stack"
        exit 1
    fi
    
    # Extract account from stack name
    ACCOUNT=$(echo "$STACK" | cut -d'-' -f2)
    
    # Validate that we got a valid account from the stack name
    if [[ -z "$ACCOUNT" ]]; then
        log "ERROR: Could not extract account name from stack: $STACK"
        log "Stack name should be in format: tenant-account-environment"
        exit 1
    fi
    
    # Handle AWS credentials for cross-account access if needed
    if [[ "$ACCOUNT" != "dev" && -n "$ACCOUNT" ]]; then
        log "Setting up cross-account access for account: $ACCOUNT"
        
        # Check if we have account credentials or need to assume role
        if [ -f "/atlantis/.aws/credentials.${ACCOUNT}" ]; then
            log "Using existing credentials for account $ACCOUNT"
            export AWS_SHARED_CREDENTIALS_FILE="/atlantis/.aws/credentials.${ACCOUNT}"
        else
            # Try to get account ID from a mapping file
            ACCOUNT_ID=""
            if [ -f "/atlantis/accounts.json" ]; then
                ACCOUNT_ID=$(jq -r ".$ACCOUNT // empty" /atlantis/accounts.json)
            fi
            
            if [ -n "$ACCOUNT_ID" ]; then
                log "Assuming role for account $ACCOUNT ($ACCOUNT_ID)"
                source assume-role.sh "$ACCOUNT_ID" "AtlantisAssumeRole" "atlantis-${ACCOUNT}" || handle_error $?
            else
                log "WARNING: No account ID mapping found for $ACCOUNT"
                log "Proceeding with current credentials"
            fi
        fi
    fi
fi

# Log command execution
log "Executing: atmos $COMMAND $*"

# Execute Atmos command with all arguments and capture output
{
    OUTPUT=$(atmos "$COMMAND" "$@" 2>&1)
    EXIT_CODE=$?
} || {
    EXIT_CODE=$?
}

# Log command output
log "$OUTPUT"

# Handle command result
if [ $EXIT_CODE -eq 0 ]; then
    log "Command completed successfully"
    echo "$OUTPUT"
    exit 0
else
    log "Command failed with exit code $EXIT_CODE"
    echo "$OUTPUT"
    exit $EXIT_CODE
fi