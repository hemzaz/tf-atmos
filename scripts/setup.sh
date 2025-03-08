#!/usr/bin/env bash
# Setup script for Atmos CLI
# This script installs the Python-based Atmos CLI

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ANSI color codes
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
RESET='\033[0m'

# Print section header
print_section() {
  echo -e "${GREEN}===${RESET} $1 ${GREEN}===${RESET}"
}

# Check Python version
check_python() {
  if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: Python 3 is required but not installed.${RESET}"
    echo "Please install Python 3.8 or higher."
    exit 1
  fi
  
  local version=$(python3 --version | cut -d' ' -f2)
  local major=$(echo "$version" | cut -d. -f1)
  local minor=$(echo "$version" | cut -d. -f2)
  
  if [[ "$major" -lt 3 || ("$major" -eq 3 && "$minor" -lt 8) ]]; then
    echo -e "${RED}Error: Python 3.8+ is required, but found $version${RESET}"
    echo "Please upgrade your Python installation."
    exit 1
  fi
  
  echo -e "${GREEN}✓${RESET} Using Python $version"
}

# Create virtual environment
create_venv() {
  if [[ -d "${REPO_ROOT}/.venv" ]]; then
    echo -e "${YELLOW}Virtual environment already exists.${RESET}"
    read -p "Recreate virtual environment? [y/N] " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
      rm -rf "${REPO_ROOT}/.venv"
    else
      echo -e "${GREEN}✓${RESET} Using existing virtual environment."
      return 0
    fi
  fi
  
  echo "Creating virtual environment..."
  python3 -m venv "${REPO_ROOT}/.venv"
  echo -e "${GREEN}✓${RESET} Virtual environment created."
}

# Install dependencies and package
install_package() {
  echo "Installing dependencies and package..."
  "${REPO_ROOT}/.venv/bin/pip" install --upgrade pip
  "${REPO_ROOT}/.venv/bin/pip" install -r "${REPO_ROOT}/requirements.txt"
  "${REPO_ROOT}/.venv/bin/pip" install -e "${REPO_ROOT}"
  echo -e "${GREEN}✓${RESET} Package installed successfully."
}

# Create convenience symlink
create_symlink() {
  local bin_dir="${REPO_ROOT}/bin"
  local symlink="${bin_dir}/atmos-cli"
  
  mkdir -p "${bin_dir}"
  
  if [[ -L "${symlink}" ]]; then
    rm "${symlink}"
  fi
  
  ln -s "${REPO_ROOT}/.venv/bin/atmos-cli" "${symlink}"
  chmod +x "${symlink}"
  
  echo -e "${GREEN}✓${RESET} Created symlink at ${symlink}"
}

# Main installation function
main() {
  print_section "Atmos CLI Installation"
  
  # Check prerequisites
  check_python
  
  # Setup environment
  create_venv
  install_package
  create_symlink
  
  print_section "Installation Complete"
  echo -e "To use Atmos CLI, you can:"
  echo -e "1. Add ${YELLOW}${REPO_ROOT}/bin${RESET} to your PATH"
  echo -e "2. Use the full path: ${YELLOW}${REPO_ROOT}/bin/atmos-cli${RESET}"
  echo -e "3. Activate the virtual environment: ${YELLOW}source ${REPO_ROOT}/.venv/bin/activate${RESET}"
  
  echo -e "\nTo verify the installation:"
  echo -e "${YELLOW}${REPO_ROOT}/bin/atmos-cli --version${RESET}"
}

# Run main function
main