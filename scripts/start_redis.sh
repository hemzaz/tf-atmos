#!/usr/bin/env bash
set -e

# Text formatting
BOLD="\033[1m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
RESET="\033[0m"

# Default values
REDIS_PORT=6379
FOREGROUND=false
REDIS_CONF="/tmp/redis.conf"

# Display help message
show_help() {
  echo -e "${BOLD}Redis Server Launcher for Atmos${RESET}"
  echo "This script starts a Redis server for Atmos asynchronous operations."
  echo
  echo -e "${BOLD}Options:${RESET}"
  echo "  -p, --port PORT       Redis port (default: 6379)"
  echo "  -f, --foreground      Run Redis in foreground (blocking)"
  echo "  -h, --help            Show this help message"
  echo
  echo -e "${BOLD}Examples:${RESET}"
  echo "  $0                    # Start Redis in background on default port"
  echo "  $0 --port 6380        # Start Redis on port 6380"
  echo "  $0 --foreground       # Start Redis in foreground (blocking)"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--port)
      REDIS_PORT="$2"
      shift 2
      ;;
    -f|--foreground)
      FOREGROUND=true
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option: $1${RESET}"
      show_help
      exit 1
      ;;
  esac
done

# Check if Redis is already installed
check_redis() {
  if ! command -v redis-server &>/dev/null; then
    echo -e "${YELLOW}Redis server not found. Attempting to install...${RESET}"
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
      if command -v brew &>/dev/null; then
        brew install redis
      else
        echo -e "${RED}Homebrew not found. Please install Redis manually:${RESET}"
        echo -e "brew install redis"
        exit 1
      fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
      # Detect package manager
      if command -v apt-get &>/dev/null; then
        sudo apt-get update
        sudo apt-get install -y redis-server
      elif command -v dnf &>/dev/null; then
        sudo dnf install -y redis
      elif command -v yum &>/dev/null; then
        sudo yum install -y redis
      else
        echo -e "${RED}Could not detect package manager. Please install Redis manually.${RESET}"
        exit 1
      fi
    else
      echo -e "${RED}Unsupported operating system: $OSTYPE${RESET}"
      echo -e "Please install Redis manually and try again."
      exit 1
    fi
  fi
  
  echo -e "${GREEN}Redis server found: $(redis-server --version)${RESET}"
}

# Check if Redis is already running
check_redis_running() {
  if command -v redis-cli &>/dev/null; then
    if redis-cli -p "$REDIS_PORT" ping &>/dev/null; then
      echo -e "${GREEN}Redis server is already running on port $REDIS_PORT${RESET}"
      return 0
    fi
  fi
  return 1
}

# Create minimal Redis configuration
create_redis_config() {
  cat > "$REDIS_CONF" << EOF
port $REDIS_PORT
daemonize yes
save ""
appendonly no
protected-mode no
EOF
}

# Start Redis server
start_redis() {
  echo -e "${BLUE}Starting Redis server on port $REDIS_PORT...${RESET}"
  
  create_redis_config
  
  if [[ "$FOREGROUND" == "true" ]]; then
    redis-server --port "$REDIS_PORT"
  else
    redis-server "$REDIS_CONF"
    
    # Check if Redis started successfully
    sleep 1
    if check_redis_running; then
      echo -e "${GREEN}Redis server started successfully.${RESET}"
      echo -e "To connect: ${BOLD}redis-cli -p $REDIS_PORT${RESET}"
      echo -e "To stop: ${BOLD}redis-cli -p $REDIS_PORT shutdown${RESET}"
      
      # Update REDIS_URL in .env if it exists
      update_env_file
    else
      echo -e "${RED}Failed to start Redis server.${RESET}"
      exit 1
    fi
  fi
}

# Update .env file with Redis URL
update_env_file() {
  local ENV_FILE="$(dirname "$0")/../.env"
  
  if [[ -f "$ENV_FILE" ]]; then
    if grep -q "REDIS_URL=" "$ENV_FILE"; then
      # Replace existing REDIS_URL
      sed -i.bak "s|REDIS_URL=.*|REDIS_URL=redis://localhost:$REDIS_PORT/0|" "$ENV_FILE" && rm -f "${ENV_FILE}.bak"
    else
      # Add REDIS_URL
      echo -e "\n# Redis configuration for async operations" >> "$ENV_FILE"
      echo "REDIS_URL=redis://localhost:$REDIS_PORT/0" >> "$ENV_FILE"
      echo "CELERY_WORKERS=4" >> "$ENV_FILE"
      echo "ASYNC_MODE=true" >> "$ENV_FILE"
    fi
    
    echo -e "${GREEN}Updated Redis configuration in $ENV_FILE${RESET}"
  fi
}

# Main function
main() {
  check_redis
  
  if check_redis_running; then
    # Redis is already running
    update_env_file
    exit 0
  fi
  
  start_redis
}

# Execute the script
main