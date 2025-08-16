#!/bin/bash
# Enhanced script to list all available Atmos stacks with friendly names
# This script provides user-friendly names and helpful context

set -euo pipefail

# Configuration
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Stack name mapping function
map_stack_name() {
    local stack="$1"
    # Convert orgs/tenant/account/region/environment to tenant-environment-account
    echo "$stack" | sed -E 's|^orgs/([^/]+)/([^/]+)/([^/]+)/([^/]+)$|\1-\4-\2|g'
}

# Reverse mapping function (friendly name to actual stack)
reverse_map_stack_name() {
    local friendly="$1"
    # Convert tenant-environment-account back to orgs/tenant/account/region/environment
    # This is a simplified version - you might need to adjust based on your naming
    if [[ "$friendly" =~ ^([^-]+)-([^-]+)-([^-]+)$ ]]; then
        local tenant="${BASH_REMATCH[1]}"
        local environment="${BASH_REMATCH[2]}" 
        local account="${BASH_REMATCH[3]}"
        local region="eu-west-2"  # Default region - could be made configurable
        echo "orgs/$tenant/$account/$region/$environment"
    else
        echo "$friendly"  # Return as-is if not matching pattern
    fi
}

echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}                     ${WHITE}Atmos Stack Listing${NC}                        ${CYAN}║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo

# Check if atmos is available
if ! command -v atmos &> /dev/null; then
    echo -e "${YELLOW}⚠️  Atmos command not found. Please install Atmos first.${NC}"
    echo -e "${BLUE}   macOS: brew install cloudposse/tap/atmos${NC}"
    echo -e "${BLUE}   Linux: Visit https://atmos.tools/install${NC}"
    exit 1
fi

# Get raw stacks
echo -e "${BLUE}🔍 Discovering available stacks...${NC}"
RAW_STACKS=$(atmos list stacks 2>/dev/null | grep -v "^$" || echo "")

if [ -z "$RAW_STACKS" ]; then
    echo -e "${YELLOW}⚠️  No stacks found!${NC}"
    echo
    echo -e "${WHITE}Possible reasons:${NC}"
    echo -e "  • Not in an Atmos project directory (look for atmos.yaml)"
    echo -e "  • No stack configurations exist in stacks/ directory"
    echo -e "  • Atmos configuration error"
    echo
    echo -e "${BLUE}💡 Try:${NC}"
    echo -e "  • Check current directory: ${WHITE}pwd${NC}"
    echo -e "  • Look for atmos.yaml: ${WHITE}ls -la atmos.yaml${NC}"
    echo -e "  • Check stacks directory: ${WHITE}ls -la stacks/${NC}"
    exit 1
fi

# Display stacks with friendly names
echo -e "${GREEN}✅ Found $(echo "$RAW_STACKS" | wc -l | tr -d ' ') stack(s)${NC}"
echo
echo -e "${WHITE}Available Environments:${NC}"
echo -e "${WHITE}======================${NC}"

# Create associative arrays (if bash 4+ is available)
declare -A STACK_MAP
declare -A REVERSE_MAP

while IFS= read -r raw_stack; do
    [ -z "$raw_stack" ] && continue
    
    friendly=$(map_stack_name "$raw_stack")
    STACK_MAP["$friendly"]="$raw_stack"
    REVERSE_MAP["$raw_stack"]="$friendly"
    
    # Extract components for display
    if [[ "$raw_stack" =~ orgs/([^/]+)/([^/]+)/([^/]+)/([^/]+) ]]; then
        tenant="${BASH_REMATCH[1]}"
        account="${BASH_REMATCH[2]}"
        region="${BASH_REMATCH[3]}"
        environment="${BASH_REMATCH[4]}"
        
        echo -e "  ${GREEN}•${NC} ${WHITE}$friendly${NC}"
        echo -e "    ${BLUE}Tenant:${NC} $tenant  ${BLUE}Account:${NC} $account  ${BLUE}Region:${NC} $region  ${BLUE}Environment:${NC} $environment"
        echo -e "    ${YELLOW}Full path:${NC} $raw_stack"
        echo
    else
        echo -e "  ${GREEN}•${NC} ${WHITE}$friendly${NC} (${YELLOW}$raw_stack${NC})"
        echo
    fi
done <<< "$RAW_STACKS"

# Show components for the first stack as an example
FIRST_STACK=$(echo "$RAW_STACKS" | head -1)
if [ -n "$FIRST_STACK" ]; then
    FIRST_FRIENDLY=$(map_stack_name "$FIRST_STACK")
    
    echo -e "${WHITE}Components in ${GREEN}$FIRST_FRIENDLY${WHITE}:${NC}"
    echo -e "${WHITE}===========================================${NC}"
    
    COMPONENTS=$(atmos list components -s "$FIRST_STACK" 2>/dev/null | grep -v "^$" || echo "")
    if [ -n "$COMPONENTS" ]; then
        while IFS= read -r component; do
            [ -z "$component" ] && continue
            echo -e "  ${CYAN}📦${NC} $component"
        done <<< "$COMPONENTS"
    else
        echo -e "  ${YELLOW}⚠️  No components found${NC}"
    fi
    echo
fi

# Usage examples
echo -e "${WHITE}Usage Examples:${NC}"
echo -e "${WHITE}===============${NC}"

if [ -n "$FIRST_STACK" ]; then
    FIRST_FRIENDLY=$(map_stack_name "$FIRST_STACK")
    echo -e "${BLUE}Using friendly names with make:${NC}"
    echo -e "  ${WHITE}make status${NC}  # Show status for default stack"
    echo -e "  ${WHITE}make plan TENANT=fnx ACCOUNT=dev ENVIRONMENT=testenv-01${NC}"
    echo -e "  ${WHITE}make apply TENANT=fnx ACCOUNT=dev ENVIRONMENT=testenv-01${NC}"
    echo
    
    echo -e "${BLUE}Using Gaia CLI (recommended):${NC}"
    if [[ "$FIRST_STACK" =~ orgs/([^/]+)/([^/]+)/([^/]+)/([^/]+) ]]; then
        tenant="${BASH_REMATCH[1]}"
        account="${BASH_REMATCH[2]}"
        environment="${BASH_REMATCH[4]}"
        echo -e "  ${WHITE}gaia status --tenant $tenant --account $account --environment $environment${NC}"
        echo -e "  ${WHITE}gaia workflow plan-environment -t $tenant -a $account -e $environment${NC}"
        echo -e "  ${WHITE}gaia workflow apply-environment -t $tenant -a $account -e $environment${NC}"
    fi
    echo
    
    echo -e "${BLUE}Using raw Atmos commands:${NC}"
    echo -e "  ${WHITE}atmos terraform plan vpc -s \"$FIRST_STACK\"${NC}"
    echo -e "  ${WHITE}atmos describe stacks -s \"$FIRST_STACK\"${NC}"
    echo
fi

# Quick commands section
echo -e "${WHITE}Quick Commands:${NC}"
echo -e "${WHITE}===============${NC}"
echo -e "  ${WHITE}make help${NC}              # Show all available make targets"
echo -e "  ${WHITE}gaia --help${NC}           # Show Gaia CLI options"
echo -e "  ${WHITE}make doctor${NC}           # Run system diagnostics"
echo -e "  ${WHITE}gaia quick-start${NC}      # Interactive getting started guide"
echo

# Export functions for other scripts to use
cat > "$REPO_ROOT/.stack_aliases" << 'EOF'
# Stack name mapping functions
# Source this file to use: source .stack_aliases

map_stack_name() {
    local stack="$1"
    echo "$stack" | sed -E 's|^orgs/([^/]+)/([^/]+)/([^/]+)/([^/]+)$|\1-\4-\2|g'
}

reverse_map_stack_name() {
    local friendly="$1"
    if [[ "$friendly" =~ ^([^-]+)-([^-]+)-([^-]+)$ ]]; then
        local tenant="${BASH_REMATCH[1]}"
        local environment="${BASH_REMATCH[2]}" 
        local account="${BASH_REMATCH[3]}"
        local region="eu-west-2"  # Default region
        echo "orgs/$tenant/$account/$region/$environment"
    else
        echo "$friendly"
    fi
}

# Convenience functions
get_stack_by_friendly() {
    local friendly="$1"
    reverse_map_stack_name "$friendly"
}

list_friendly_stacks() {
    atmos list stacks 2>/dev/null | while read -r stack; do
        [ -z "$stack" ] && continue
        map_stack_name "$stack"
    done
}
EOF

echo -e "${GREEN}✅ Stack listing complete!${NC}"
echo -e "${BLUE}💡 Stack mapping functions saved to .stack_aliases${NC}"