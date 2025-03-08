#!/usr/bin/env bash
# Centralized logging utility for Atmos scripts
# DEPRECATED: Use the Python implementation in atmos_cli/logger.py instead

# Print deprecation notice - only in interactive mode and if not sourced
if [[ -t 1 && "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "⚠️  DEPRECATION NOTICE: This logger.sh script is deprecated."
  echo "Please use the Python implementation in atmos_cli/logger.py for new code."
fi

# Log levels
LEVEL_DEBUG=10
LEVEL_INFO=20
LEVEL_WARN=30
LEVEL_ERROR=40
LEVEL_FATAL=50

# Current log level (default: INFO)
LOG_LEVEL=${LOG_LEVEL:-$LEVEL_INFO}

# Output formatting
BOLD="\033[1m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
PURPLE="\033[35m"
CYAN="\033[36m"
GRAY="\033[90m"
RESET="\033[0m"

# Emoji prefixes
EMOJI_DEBUG="🔍"
EMOJI_INFO="ℹ️ "
EMOJI_SUCCESS="✅"
EMOJI_WARN="⚠️ "
EMOJI_ERROR="❌"
EMOJI_FATAL="🚨"

# Enable/disable colors
USE_COLORS=${USE_COLORS:-true}
USE_EMOJI=${USE_EMOJI:-true}

# Determine if script is running in CI/CD environment
is_ci_environment() {
  if [[ -n "${CI}" || -n "${GITHUB_ACTIONS}" || -n "${GITLAB_CI}" || -n "${TF_BUILD}" ]]; then
    echo "true"
  else
    echo "false"
  fi
}

# Auto-detect CI environment for color/emoji settings
if [[ "$(is_ci_environment)" == "true" ]]; then
  USE_COLORS=${USE_COLORS:-false}
  USE_EMOJI=${USE_EMOJI:-false}
fi

# Internal logging function
_log() {
  local level=$1
  local level_name=$2
  local emoji=$3
  local color=$4
  local message="${@:5}"
  
  # Check if level meets minimum log level threshold
  if [[ $level -lt $LOG_LEVEL ]]; then
    return 0
  fi
  
  # Format the message
  local prefix=""
  
  # Add level name with appropriate color
  if [[ "$USE_COLORS" == "true" ]]; then
    prefix="${color}${level_name}${RESET} "
  else
    prefix="${level_name} "
  fi
  
  # Add emoji if enabled
  if [[ "$USE_EMOJI" == "true" ]]; then
    prefix="${emoji} ${prefix}"
  fi
  
  # Add timestamp if not in CI
  if [[ "$(is_ci_environment)" != "true" ]]; then
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    prefix="[${timestamp}] ${prefix}"
  fi
  
  # Output the message
  echo -e "${prefix}${message}"
}

# Public logging functions
log_debug() {
  _log $LEVEL_DEBUG "DEBUG" "${EMOJI_DEBUG}" "${GRAY}" "$@"
}

log_info() {
  _log $LEVEL_INFO "INFO" "${EMOJI_INFO}" "${BLUE}" "$@"
}

log_success() {
  _log $LEVEL_INFO "SUCCESS" "${EMOJI_SUCCESS}" "${GREEN}" "$@"
}

log_warn() {
  _log $LEVEL_WARN "WARNING" "${EMOJI_WARN}" "${YELLOW}" "$@" >&2
}

log_error() {
  _log $LEVEL_ERROR "ERROR" "${EMOJI_ERROR}" "${RED}" "$@" >&2
}

log_fatal() {
  _log $LEVEL_FATAL "FATAL" "${EMOJI_FATAL}" "${BOLD}${RED}" "$@" >&2
  exit 1
}

# Helper to horizontally separate sections
log_section() {
  local title="$1"
  local char="${2:-=}"
  local width=60
  
  if [[ -n "$title" ]]; then
    local padding=$(( (width - ${#title} - 2) / 2 ))
    local line=$(printf "%*s" "$padding" | tr ' ' "$char")
    log_info "${line} ${title} ${line}"
  else
    log_info "$(printf "%*s" "$width" | tr ' ' "$char")"
  fi
}

# Set environment variables based on verbose flags (for CLI tools)
setup_verbosity() {
  if [[ "$LOG_LEVEL" -le "$LEVEL_DEBUG" ]]; then
    export TF_LOG=DEBUG
    export VERBOSE=1
    export ATMOS_VERBOSE=true
  elif [[ "$LOG_LEVEL" -le "$LEVEL_INFO" ]]; then
    export TF_LOG=INFO
    unset VERBOSE
    export ATMOS_VERBOSE=false
  else
    export TF_LOG=ERROR
    unset VERBOSE
    export ATMOS_VERBOSE=false
  fi
}

# Allow setting log level by name
set_log_level() {
  local level_name="$1"
  
  case "${level_name^^}" in
    DEBUG) LOG_LEVEL=$LEVEL_DEBUG ;;
    INFO)  LOG_LEVEL=$LEVEL_INFO ;;
    WARN)  LOG_LEVEL=$LEVEL_WARN ;;
    ERROR) LOG_LEVEL=$LEVEL_ERROR ;;
    FATAL) LOG_LEVEL=$LEVEL_FATAL ;;
    *)     log_warn "Unknown log level: $level_name. Using INFO." 
           LOG_LEVEL=$LEVEL_INFO ;;
  esac
  
  setup_verbosity
}

# Initialize based on verbose flag from environment
if [[ "${VERBOSE}" == "1" || "${DEBUG}" == "1" || "${ATMOS_VERBOSE}" == "true" ]]; then
  set_log_level DEBUG
fi