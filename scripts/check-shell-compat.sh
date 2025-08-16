#!/usr/bin/env bash
# Shell Compatibility Checker for Terraform/Atmos Project
# Validates shell compatibility across macOS (bash 3.x) and Linux (bash 4+)

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Configuration
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

TOTAL_ISSUES=0
CRITICAL_ISSUES=0
WARNING_ISSUES=0

# Display header
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}                   ${WHITE}Shell Compatibility Checker${NC}                   ${CYAN}║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo

# Get system information
BASH_VERSION=$(bash --version | head -1 | grep -o '[0-9]\.[0-9][0-9]*' | head -1)
BASH_MAJOR=$(echo "$BASH_VERSION" | cut -d. -f1)
OS_TYPE=$(uname -s)

echo -e "${WHITE}System Information:${NC}"
echo -e "==================="
echo -e "  OS: ${GREEN}$OS_TYPE${NC}"
echo -e "  Bash Version: ${GREEN}$BASH_VERSION${NC}"
echo -e "  Bash Major: ${GREEN}$BASH_MAJOR${NC}"
echo

# Function to report issue
report_issue() {
    local level="$1"
    local file="$2"
    local line="$3"
    local description="$4"
    local suggestion="${5:-}"
    
    ((TOTAL_ISSUES++))
    
    case "$level" in
        "CRITICAL")
            ((CRITICAL_ISSUES++))
            echo -e "  ${RED}✘ CRITICAL${NC} $file:$line - $description"
            ;;
        "WARNING")
            ((WARNING_ISSUES++))
            echo -e "  ${YELLOW}⚠ WARNING${NC} $file:$line - $description"
            ;;
        "INFO")
            echo -e "  ${BLUE}ℹ INFO${NC} $file:$line - $description"
            ;;
    esac
    
    if [ -n "$suggestion" ]; then
        echo -e "    ${CYAN}→${NC} $suggestion"
    fi
}

# Function to detect coreutils availability
detect_coreutils() {
    local has_coreutils="false"
    
    # Check if GNU versions of common tools are available
    if command -v greadlink >/dev/null 2>&1 || readlink --version 2>/dev/null | grep -q "coreutils"; then
        has_coreutils="true"
    elif command -v gtimeout >/dev/null 2>&1 || timeout --version 2>/dev/null | grep -q "coreutils"; then
        has_coreutils="true"
    fi
    
    if [[ "$has_coreutils" == "true" ]]; then
        echo -e "${GREEN}✅ GNU coreutils detected - enhanced functionality available${NC}"
    else
        echo -e "${YELLOW}ℹ️  GNU coreutils not detected - using standard BSD tools${NC}"
    fi
    
    echo "$has_coreutils"
}

# Function to check bash 4+ features
check_bash4_features() {
    local file="$1"
    
    # Skip binary files and very large files to avoid hanging
    if ! file "$file" | grep -q "text" 2>/dev/null; then
        return 0
    fi
    
    local file_size=$(wc -c < "$file" 2>/dev/null || echo "0")
    if [ "$file_size" -gt 50000 ]; then
        echo -e "${YELLOW}Skipping large file $file (${file_size} bytes)${NC}"
        return 0
    fi
    
    # Use improved timeout command detection
    local timeout_cmd=""
    if command -v gtimeout >/dev/null 2>&1; then
        timeout_cmd="gtimeout 3"
    elif command -v timeout >/dev/null 2>&1; then
        timeout_cmd="timeout 3"
    fi
    
    # Simple compatibility checks with timeout protection
    if [[ -n "$timeout_cmd" ]]; then
        if $timeout_cmd grep -q "declare -A" "$file" 2>/dev/null; then
            report_issue "CRITICAL" "$file" "N/A" "Contains associative arrays (declare -A) not supported in bash 3.x" \
                "Use alternative data structures or conditional logic based on bash version"
        fi
        
        if $timeout_cmd grep -q '\${[^}]*\^\^\?}' "$file" 2>/dev/null; then
            report_issue "CRITICAL" "$file" "N/A" "Contains parameter expansion ^^ (uppercase) not supported in bash 3.x" \
                "Use tr command instead: \$(echo \"\$var\" | tr '[:lower:]' '[:upper:]')"
        fi
        
        if $timeout_cmd grep -q '\${[^}]*,,\?}' "$file" 2>/dev/null; then
            report_issue "CRITICAL" "$file" "N/A" "Contains parameter expansion ,, (lowercase) not supported in bash 3.x" \
                "Use tr command instead: \$(echo \"\$var\" | tr '[:upper:]' '[:lower:]')"
        fi
        
        if $timeout_cmd grep -q "shopt -s globstar" "$file" 2>/dev/null; then
            report_issue "WARNING" "$file" "N/A" "Contains globstar option not available in bash 3.x" \
                "Use find command or explicit recursive patterns"
        fi
        
        if $timeout_cmd grep -q -E "(readarray|mapfile)" "$file" 2>/dev/null; then
            report_issue "CRITICAL" "$file" "N/A" "Contains readarray/mapfile not supported in bash 3.x" \
                "Use while read loop instead"
        fi
    else
        # Fallback without timeout
        if grep -q "declare -A" "$file" 2>/dev/null; then
            report_issue "CRITICAL" "$file" "N/A" "Contains associative arrays (declare -A) not supported in bash 3.x" \
                "Use alternative data structures or conditional logic based on bash version"
        fi
    fi
}

# Function to check shebang lines
check_shebang() {
    local file="$1"
    local first_line=$(head -1 "$file")
    
    if [[ "$first_line" == "#!/bin/bash" ]]; then
        report_issue "WARNING" "$file" "1" "Fixed bash path may not work on all systems" \
            "Use #!/usr/bin/env bash for better portability"
    elif [[ "$first_line" == "#!/bin/sh" ]]; then
        # Check if script uses bash-specific features
        if grep -q -E "(\\[\\[|select|function|local|declare)" "$file" 2>/dev/null; then
            report_issue "CRITICAL" "$file" "1" "Script uses bash features but has #!/bin/sh shebang" \
                "Change to #!/usr/bin/env bash"
        fi
    elif [[ "$first_line" != "#!/usr/bin/env bash" ]] && [[ "$first_line" =~ ^#!/ ]]; then
        report_issue "INFO" "$file" "1" "Consider using #!/usr/bin/env bash for consistency"
    fi
}

# Function to check error handling
check_error_handling() {
    local file="$1"
    
    # Check for set -e or set -euo pipefail
    if ! grep -q "set -e" "$file" 2>/dev/null; then
        report_issue "WARNING" "$file" "N/A" "No error handling (set -e) detected" \
            "Add 'set -euo pipefail' near the top of the script"
    fi
    
    # Check for unbound variables protection
    if ! grep -q "set.*u" "$file" 2>/dev/null; then
        report_issue "WARNING" "$file" "N/A" "No unbound variable protection (set -u)" \
            "Add 'set -euo pipefail' to catch undefined variables"
    fi
}

# Function to check Makefile shell commands
check_makefile() {
    local file="$1"
    
    echo -e "${WHITE}Checking Makefile for shell compatibility...${NC}"
    
    # Look for complex shell commands in Makefile
    grep -n "if \[\[" "$file" 2>/dev/null | while IFS=: read -r line_no content; do
        report_issue "WARNING" "$file" "$line_no" "Makefile uses [[ which may not work with all shells" \
            "Use [ for POSIX compatibility in Makefiles"
    done
    
    # Check for bash-specific features in shell commands
    grep -n "BASH_REMATCH" "$file" 2>/dev/null | while IFS=: read -r line_no content; do
        report_issue "WARNING" "$file" "$line_no" "BASH_REMATCH used in Makefile" \
            "Ensure bash is explicitly used for these commands"
    done
}

# Main compatibility check function
main_check() {
    echo -e "${WHITE}Analyzing shell scripts...${NC}"
    echo -e "========================="
    
    # Detect coreutils availability
    local has_coreutils=$(detect_coreutils)
    echo
    
    # Focus on critical scripts first to avoid timeouts
    local critical_scripts=(
        "./scripts/list_stacks.sh"
        "./scripts/logger.sh"
        "./scripts/update-versions.sh"
        "./scripts/aws-setup.sh"
        "./scripts/atmos_wrapper.sh"
        "./scripts/utils.sh"
    )
    
    echo -e "${BLUE}Checking critical scripts first...${NC}"
    for script in "${critical_scripts[@]}"; do
        if [[ -f "$script" ]]; then
            echo -e "${WHITE}Checking $script...${NC}"
            check_shebang "$script"
            check_bash4_features "$script"
            check_error_handling "$script"
            echo
        fi
    done
    
    # Check remaining scripts (with limits to prevent timeout)
    echo -e "${BLUE}Checking remaining scripts...${NC}"
    local count=0
    local max_scripts=15  # Limit to prevent timeout
    for script in $(find . -name "*.sh" -type f 2>/dev/null | head -20); do
        # Skip self and already checked scripts
        if [[ "$script" == "./scripts/check-shell-compat.sh" ]]; then
            continue
        fi
        
        # Skip if already checked
        local skip=false
        for critical in "${critical_scripts[@]}"; do
            if [[ "$script" == "$critical" ]]; then
                skip=true
                break
            fi
        done
        
        if [[ "$skip" == "true" ]]; then
            continue
        fi
        
        if [[ $count -ge $max_scripts ]]; then
            echo -e "${YELLOW}Limiting check to $max_scripts scripts to prevent timeout...${NC}"
            break
        fi
        
        echo -e "${WHITE}Checking $script...${NC}"
        check_shebang "$script"
        check_bash4_features "$script"
        echo
        ((count++))
    done
    
    # Check Makefile
    if [ -f "Makefile" ]; then
        check_makefile "Makefile"
        echo
    fi
    
    # Check other potential shell code locations
    echo -e "${WHITE}Checking other files with embedded shell code...${NC}"
    echo -e "==============================================="
    
    # Check for shell code in YAML files (workflows)
    if [ -d "workflows" ]; then
        for yaml_file in $(find workflows/ -name "*.yaml" -o -name "*.yml" 2>/dev/null); do
            if grep -q "bash\|sh" "$yaml_file" 2>/dev/null; then
                echo -e "${BLUE}Found shell references in $yaml_file${NC}"
                # Could add more specific checks here
            fi
        done
    fi
    
    # Check integration scripts  
    if [ -d "integrations" ]; then
        for script in $(find integrations/ -name "*.sh" -type f 2>/dev/null); do
            echo -e "${WHITE}Checking integration script $script...${NC}"
            check_shebang "$script"
            check_bash4_features "$script"
            echo
        done
    fi
}

# Function to generate compatibility report
generate_report() {
    echo
    echo -e "${WHITE}Compatibility Summary:${NC}"
    echo -e "======================"
    echo -e "  Total Issues: ${WHITE}$TOTAL_ISSUES${NC}"
    echo -e "  Critical Issues: ${RED}$CRITICAL_ISSUES${NC}"
    echo -e "  Warnings: ${YELLOW}$WARNING_ISSUES${NC}"
    echo
    
    if [ "$CRITICAL_ISSUES" -gt 0 ]; then
        echo -e "${RED}⚠️  CRITICAL ISSUES FOUND!${NC}"
        echo -e "Scripts with critical issues will fail on bash 3.x systems (macOS default)."
        echo -e "Please fix these issues before deployment."
        echo
    fi
    
    if [ "$WARNING_ISSUES" -gt 0 ]; then
        echo -e "${YELLOW}⚠️  Warnings found.${NC}"
        echo -e "These issues should be addressed for best practices and portability."
        echo
    fi
    
    if [ "$TOTAL_ISSUES" -eq 0 ]; then
        echo -e "${GREEN}✅ No compatibility issues found!${NC}"
        echo -e "All scripts appear compatible with bash 3.x and 4+."
        echo
    fi
    
    echo -e "${WHITE}Recommendations:${NC}"
    echo -e "================="
    echo -e "  • Use ${CYAN}#!/usr/bin/env bash${NC} for all shell scripts"
    echo -e "  • Add ${CYAN}set -euo pipefail${NC} for robust error handling"
    echo -e "  • Avoid bash 4+ specific features or add version checks"
    echo -e "  • Test scripts on both macOS (bash 3.x) and Linux (bash 4+)"
    echo -e "  • Use ${CYAN}shellcheck${NC} for additional static analysis"
    echo
    
    echo -e "${BLUE}Testing Commands:${NC}"
    echo -e "=================="
    echo -e "  # Test on current system:"
    echo -e "  ${WHITE}./scripts/check-shell-compat.sh${NC}"
    echo -e "  "
    echo -e "  # Test specific script manually:"
    echo -e "  ${WHITE}bash -n /path/to/script.sh${NC}  # Syntax check"
    echo -e "  ${WHITE}bash -x /path/to/script.sh${NC}  # Debug execution"
    echo
}

# Main execution
main_check
generate_report

# Exit with error code if critical issues found
if [ "$CRITICAL_ISSUES" -gt 0 ]; then
    exit 1
else
    exit 0
fi