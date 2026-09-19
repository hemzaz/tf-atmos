#!/bin/bash
set -eo pipefail

# Wrapper script for Atmos to provide better error handling and logging
# Usage: atmos-wrapper.sh [command] [args...]

# Log file locations
LOG_DIR="${ATMOS_WRAPPER_LOG_DIR:-/atlantis/logs}"
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
    log "Example: atmos-wrapper.sh terraform plan vpc/main -s fnx-dev-testenv-01"
    exit 1
fi

COMMAND="$1"
shift

# Check if component and stack are specified for terraform commands
if [[ "$COMMAND" == "terraform" ]]; then
    # For terraform commands, we need at least a subcommand and a component
    if [ $# -lt 2 ]; then
        log "For terraform commands, you must specify a subcommand and component"
        log "Example: atmos-wrapper.sh terraform plan vpc/main -s fnx-dev-testenv-01"
        exit 1
    fi
    
    SUBCOMMAND="$1"
    COMPONENT="$2"
    shift 2
    # Put them back so the final atmos call receives the full command line
    set -- "$SUBCOMMAND" "$COMPONENT" "$@"
    
    # Check if stack is specified
    STACK=""
    idx=0
    for i in "$@"; do
        if [[ "$i" == "-s" || "$i" == "--stack" ]]; then
            # The value follows the flag: 0-based idx+1, i.e. positional idx+2
            if [ $((idx+1)) -lt $# ]; then
                STACK="${*:$((idx+2)):1}"
                break
            fi
        fi
        idx=$((idx+1))
    done
    
    if [[ -z "$STACK" ]]; then
        log "ERROR: Stack must be specified with -s or --stack"
        exit 1
    fi
    
    # Resolve the account from the stack configuration (settings.environment.account);
    # stack names are <tenant>-<stage>-<environment> and do not carry it
    ACCOUNT=$(atmos describe component "$COMPONENT" -s "$STACK" --process-functions=false --format json \
        | jq -r '.settings.environment.account // empty')
    
    if [[ -z "$ACCOUNT" ]]; then
        log "ERROR: Could not resolve settings.environment.account for $COMPONENT in stack: $STACK"
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