#!/usr/bin/env bash

# Gaia API - Terminal Power User Examples
# 
# This script demonstrates curl-based infrastructure management using the Gaia API
# For maximum terminal ergonomics and power-user workflows
#
# Usage:
#   ./scripts/curl-examples.sh                    # Show all examples
#   ./scripts/curl-examples.sh list-stacks       # Run specific example
#   ./scripts/curl-examples.sh validate-stack    # Run validation example

set -euo pipefail

API_HOST="localhost"
API_PORT="8080"
API_BASE="http://${API_HOST}:${API_PORT}"

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}🌍 Gaia API - Terminal Power User Examples${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

print_example() {
    local title="$1"
    local description="$2"
    local command="$3"
    
    echo -e "${YELLOW}📝 ${title}${NC}"
    echo -e "${PURPLE}   ${description}${NC}"
    echo -e "${GREEN}   ${command}${NC}"
    echo ""
}

print_separator() {
    echo -e "${BLUE}────────────────────────────────────────────────────────────────────────────────${NC}"
    echo ""
}

check_api_server() {
    if ! curl -s "${API_BASE}/health" > /dev/null 2>&1; then
        echo -e "${RED}❌ Gaia API server not running on ${API_BASE}${NC}"
        echo -e "${YELLOW}💡 Start it with: gaia serve${NC}"
        echo ""
        exit 1
    fi
    echo -e "${GREEN}✅ API server running at ${API_BASE}${NC}"
    echo ""
}

run_example() {
    local example_name="$1"
    
    case "$example_name" in
        "api-docs")
            echo -e "${CYAN}📖 API Documentation${NC}"
            curl -s "${API_BASE}/" | jq '.'
            ;;
        "health-check")
            echo -e "${CYAN}🩺 Health Check${NC}"
            curl -s "${API_BASE}/health" | jq '.'
            ;;
        "list-stacks")
            echo -e "${CYAN}📋 List All Stacks${NC}"
            curl -s "${API_BASE}/stacks" | jq '.'
            ;;
        "list-components")
            echo -e "${CYAN}📦 List All Components${NC}"
            curl -s "${API_BASE}/components" | jq '.'
            ;;
        "stack-components")
            echo -e "${CYAN}🔍 Components in fnx-dev-testenv-01 Stack${NC}"
            curl -s "${API_BASE}/stacks/fnx-dev-testenv-01/components" | jq '.'
            ;;
        "validate-stack")
            echo -e "${CYAN}✅ Validate fnx-dev-testenv-01 Stack${NC}"
            curl -s -X POST "${API_BASE}/stacks/fnx-dev-testenv-01/validate" | jq '.'
            ;;
        "validate-component")
            echo -e "${CYAN}🧪 Validate VPC Component${NC}"
            curl -s -X POST -H "Content-Type: application/json" \
                 -d '{"stack":"fnx-dev-testenv-01"}' \
                 "${API_BASE}/components/vpc/validate" | jq '.'
            ;;
        "plan-component")
            echo -e "${CYAN}📋 Plan VPC Component${NC}"
            curl -s -X POST -H "Content-Type: application/json" \
                 -d '{"component":"vpc"}' \
                 "${API_BASE}/stacks/fnx-dev-testenv-01/plan" | jq '.'
            ;;
        "lint-all")
            echo -e "${CYAN}🧹 Lint All Configurations${NC}"
            curl -s -X POST "${API_BASE}/lint" | jq '.'
            ;;
        "validate-all")
            echo -e "${CYAN}✅ Validate All Configurations${NC}"
            curl -s -X POST "${API_BASE}/validate" | jq '.'
            ;;
        "list-workflows")
            echo -e "${CYAN}⚡ List Available Workflows${NC}"
            curl -s "${API_BASE}/workflows" | jq '.'
            ;;
        "run-workflow-lint")
            echo -e "${CYAN}🔧 Run Lint Workflow${NC}"
            curl -s -X POST "${API_BASE}/workflows/lint" | jq '.'
            ;;
        "run-workflow-validate")
            echo -e "${CYAN}🔍 Run Validate Workflow${NC}"
            curl -s -X POST -H "Content-Type: application/json" \
                 -d '{"tenant":"fnx","account":"dev","environment":"testenv-01"}' \
                 "${API_BASE}/workflows/validate" | jq '.'
            ;;
        "status")
            echo -e "${CYAN}📊 System Status${NC}"
            curl -s "${API_BASE}/status" | jq '.'
            ;;
        *)
            echo -e "${RED}❌ Unknown example: $example_name${NC}"
            exit 1
            ;;
    esac
}

show_power_user_workflows() {
    print_separator
    echo -e "${PURPLE}🔥 Power User Workflow Patterns${NC}"
    print_separator
    
    echo -e "${YELLOW}📝 Daily Development Workflow${NC}"
    echo -e "   ${GREEN}# Quick validation check${NC}"
    echo -e "   ${GREEN}curl -s ${API_BASE}/validate | jq '.success'${NC}"
    echo ""
    echo -e "   ${GREEN}# List and validate specific stack${NC}"
    echo -e "   ${GREEN}STACK=\$(curl -s ${API_BASE}/stacks | jq -r '.stacks[0]')${NC}"
    echo -e "   ${GREEN}curl -X POST ${API_BASE}/stacks/\$STACK/validate | jq '.summary'${NC}"
    echo ""
    
    echo -e "${YELLOW}📝 Component Development Cycle${NC}"
    echo -e "   ${GREEN}# Lint -> Validate -> Plan workflow${NC}"
    echo -e "   ${GREEN}curl -X POST ${API_BASE}/lint && \\${NC}"
    echo -e "   ${GREEN}curl -X POST -d '{\"stack\":\"fnx-dev-testenv-01\"}' ${API_BASE}/components/vpc/validate && \\${NC}"
    echo -e "   ${GREEN}curl -X POST -d '{\"component\":\"vpc\"}' ${API_BASE}/stacks/fnx-dev-testenv-01/plan${NC}"
    echo ""
    
    echo -e "${YELLOW}📝 Environment Health Check${NC}"
    echo -e "   ${GREEN}# Complete environment status in one line${NC}"
    echo -e "   ${GREEN}curl -s ${API_BASE}/status | jq '{stacks: .summary.total_stacks, health: .summary}'${NC}"
    echo ""
    
    echo -e "${YELLOW}📝 Batch Operations${NC}"
    echo -e "   ${GREEN}# Validate all components in all stacks${NC}"
    echo -e "   ${GREEN}for stack in \$(curl -s ${API_BASE}/stacks | jq -r '.stacks[]'); do${NC}"
    echo -e "   ${GREEN}  echo \"Validating \$stack...\"${NC}"
    echo -e "   ${GREEN}  curl -X POST ${API_BASE}/stacks/\$stack/validate | jq '.summary'${NC}"
    echo -e "   ${GREEN}done${NC}"
    echo ""
    
    echo -e "${YELLOW}📝 JSON Processing & Filtering${NC}"
    echo -e "   ${GREEN}# Get only failed validations${NC}"
    echo -e "   ${GREEN}curl -X POST ${API_BASE}/stacks/fnx-dev-testenv-01/validate | \\${NC}"
    echo -e "   ${GREEN}  jq '.results[] | select(.success == false)'${NC}"
    echo ""
    echo -e "   ${GREEN}# Count components by type${NC}"
    echo -e "   ${GREEN}curl -s ${API_BASE}/components | jq '.components | group_by(.) | map({component: .[0], count: length})'${NC}"
    echo ""
}

show_advanced_examples() {
    print_separator
    echo -e "${PURPLE}⚡ Advanced Terminal Integration${NC}"
    print_separator
    
    echo -e "${YELLOW}📝 Shell Functions (add to ~/.bashrc or ~/.zshrc)${NC}"
    cat << 'EOF'
   # Quick Gaia API functions
   gaia-status() { curl -s http://localhost:8080/status | jq '.summary'; }
   gaia-stacks() { curl -s http://localhost:8080/stacks | jq -r '.stacks[]'; }
   gaia-validate() { 
     local stack=${1:-fnx-dev-testenv-01}
     curl -X POST http://localhost:8080/stacks/$stack/validate | jq '.summary'
   }
   gaia-lint() { curl -X POST http://localhost:8080/lint | jq -r '.stdout'; }
   
   # Component operations
   gaia-plan() {
     local component=${1:?Component required}
     local stack=${2:-fnx-dev-testenv-01}
     curl -X POST -H "Content-Type: application/json" \
          -d "{\"component\":\"$component\"}" \
          http://localhost:8080/stacks/$stack/plan | jq -r '.stdout'
   }
EOF
    echo ""
    
    echo -e "${YELLOW}📝 Watch Mode (continuous monitoring)${NC}"
    echo -e "   ${GREEN}# Watch stack validation status every 30 seconds${NC}"
    echo -e "   ${GREEN}watch -n 30 'curl -s ${API_BASE}/stacks/fnx-dev-testenv-01/validate | jq \".summary\"'${NC}"
    echo ""
    
    echo -e "${YELLOW}📝 Error Handling & Retry Logic${NC}"
    cat << 'EOF'
   # Robust validation with retry
   validate_with_retry() {
     local stack=${1:-fnx-dev-testenv-01}
     local retries=3
     
     for i in $(seq 1 $retries); do
       echo "Attempt $i/$retries..."
       if curl -X POST http://localhost:8080/stacks/$stack/validate | jq -e '.success'; then
         echo "✅ Validation successful"
         return 0
       fi
       sleep 5
     done
     echo "❌ Validation failed after $retries attempts"
     return 1
   }
EOF
    echo ""
}

show_integration_examples() {
    print_separator
    echo -e "${PURPLE}🔗 CI/CD & Automation Integration${NC}"
    print_separator
    
    echo -e "${YELLOW}📝 GitHub Actions Example${NC}"
    cat << 'EOF'
   # .github/workflows/infrastructure.yml
   - name: Validate Infrastructure
     run: |
       # Start Gaia API server
       gaia serve --port 8080 &
       sleep 5
       
       # Run validation
       RESULT=$(curl -X POST http://localhost:8080/validate)
       SUCCESS=$(echo $RESULT | jq -r '.success')
       
       if [ "$SUCCESS" != "true" ]; then
         echo "❌ Infrastructure validation failed"
         echo $RESULT | jq '.stderr'
         exit 1
       fi
       
       echo "✅ Infrastructure validation passed"
EOF
    echo ""
    
    echo -e "${YELLOW}📝 Makefile Integration${NC}"
    cat << 'EOF'
   # Add to Makefile
   api-validate:
   	@echo "🔍 Validating via API..."
   	@curl -X POST http://localhost:8080/validate | jq '.success'
   
   api-lint:
   	@echo "🧹 Linting via API..."
   	@curl -X POST http://localhost:8080/lint | jq -r '.stdout'
   
   api-status:
   	@echo "📊 Infrastructure Status:"
   	@curl -s http://localhost:8080/status | jq '.summary'
EOF
    echo ""
    
    echo -e "${YELLOW}📝 Monitoring & Alerting${NC}"
    echo -e "   ${GREEN}# Simple health monitoring script${NC}"
    cat << 'EOF'
   #!/bin/bash
   # monitor-infrastructure.sh
   
   API_BASE="http://localhost:8080"
   SLACK_WEBHOOK="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
   
   # Check API health
   if ! curl -f -s $API_BASE/health > /dev/null; then
     curl -X POST -H 'Content-type: application/json' \
          --data '{"text":"🚨 Gaia API server is down!"}' \
          $SLACK_WEBHOOK
     exit 1
   fi
   
   # Check validation status
   VALIDATION=$(curl -s -X POST $API_BASE/validate | jq -r '.success')
   if [ "$VALIDATION" != "true" ]; then
     curl -X POST -H 'Content-type: application/json' \
          --data '{"text":"⚠️ Infrastructure validation failing"}' \
          $SLACK_WEBHOOK
   fi
EOF
    echo ""
}

main() {
    if [[ $# -eq 0 ]]; then
        print_header
        check_api_server
        
        echo -e "${BLUE}🎯 Basic API Operations${NC}"
        print_example "API Documentation" "Get complete API reference" "curl ${API_BASE}/"
        print_example "Health Check" "Verify API server status" "curl ${API_BASE}/health"
        print_example "List Stacks" "Show all available stacks" "curl ${API_BASE}/stacks"
        print_example "List Components" "Show all Terraform components" "curl ${API_BASE}/components"
        print_example "Stack Components" "List components in specific stack" "curl ${API_BASE}/stacks/fnx-dev-testenv-01/components"
        
        print_separator
        echo -e "${BLUE}⚡ Operations${NC}"
        print_example "Validate Stack" "Validate all components in stack" "curl -X POST ${API_BASE}/stacks/fnx-dev-testenv-01/validate"
        print_example "Validate Component" "Validate specific component" "curl -X POST -H 'Content-Type: application/json' -d '{\"stack\":\"fnx-dev-testenv-01\"}' ${API_BASE}/components/vpc/validate"
        print_example "Plan Component" "Plan changes for component" "curl -X POST -H 'Content-Type: application/json' -d '{\"component\":\"vpc\"}' ${API_BASE}/stacks/fnx-dev-testenv-01/plan"
        print_example "Lint All" "Lint all configurations" "curl -X POST ${API_BASE}/lint"
        print_example "Global Validate" "Validate entire infrastructure" "curl -X POST ${API_BASE}/validate"
        
        print_separator
        echo -e "${BLUE}🔧 Workflows${NC}"
        print_example "List Workflows" "Show available workflows" "curl ${API_BASE}/workflows"
        print_example "Run Lint Workflow" "Execute lint workflow" "curl -X POST ${API_BASE}/workflows/lint"
        print_example "Run Validate Workflow" "Execute validation with parameters" "curl -X POST -H 'Content-Type: application/json' -d '{\"tenant\":\"fnx\",\"account\":\"dev\",\"environment\":\"testenv-01\"}' ${API_BASE}/workflows/validate"
        print_example "System Status" "Get overall system status" "curl ${API_BASE}/status"
        
        show_power_user_workflows
        show_advanced_examples  
        show_integration_examples
        
        print_separator
        echo -e "${CYAN}🚀 To run specific examples:${NC}"
        echo -e "${GREEN}   ./scripts/curl-examples.sh list-stacks${NC}"
        echo -e "${GREEN}   ./scripts/curl-examples.sh validate-stack${NC}"
        echo -e "${GREEN}   ./scripts/curl-examples.sh health-check${NC}"
        echo ""
        
    else
        check_api_server
        run_example "$1"
    fi
}

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}⚠️  jq not installed. Output will be raw JSON.${NC}"
    echo -e "${YELLOW}💡 Install with: brew install jq  (macOS) or  apt install jq  (Linux)${NC}"
    echo ""
fi

main "$@"