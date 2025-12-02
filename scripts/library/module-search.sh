#!/bin/bash
#
# Module Search and Discovery Tool
# Provides intelligent search and discovery for the Terraform module library
#
# Usage:
#   ./module-search.sh search <query>
#   ./module-search.sh list [category]
#   ./module-search.sh info <module>
#   ./module-search.sh recommend <use-case>
#   ./module-search.sh deps <module>
#   ./module-search.sh cost <module>
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REGISTRY_FILE="${PROJECT_ROOT}/stacks/catalog/_library/module-registry.yaml"
CATALOG_FILE="${PROJECT_ROOT}/stacks/catalog/_library/catalog.yaml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Check for required tools
check_requirements() {
    if ! command -v yq &> /dev/null; then
        echo -e "${RED}Error: yq is required but not installed.${NC}"
        echo "Install with: brew install yq"
        exit 1
    fi
}

# Print header
print_header() {
    echo ""
    echo -e "${BOLD}${BLUE}========================================${NC}"
    echo -e "${BOLD}${BLUE}  $1${NC}"
    echo -e "${BOLD}${BLUE}========================================${NC}"
    echo ""
}

# Print module summary
print_module_summary() {
    local module=$1

    local name=$(yq eval ".modules.${module}.display_name // \"${module}\"" "$REGISTRY_FILE")
    local category=$(yq eval ".modules.${module}.category // \"unknown\"" "$REGISTRY_FILE")
    local maturity=$(yq eval ".modules.${module}.maturity // \"unknown\"" "$REGISTRY_FILE")
    local complexity=$(yq eval ".modules.${module}.complexity // \"unknown\"" "$REGISTRY_FILE")
    local description=$(yq eval ".modules.${module}.short_description // \"No description\"" "$REGISTRY_FILE")

    # Maturity color coding
    local maturity_color=$NC
    case $maturity in
        "production") maturity_color=$GREEN ;;
        "stable") maturity_color=$BLUE ;;
        "beta") maturity_color=$YELLOW ;;
        "experimental") maturity_color=$RED ;;
    esac

    printf "${BOLD}%-25s${NC} ${maturity_color}[%s]${NC}\n" "$module" "$maturity"
    printf "  ${CYAN}%s${NC}\n" "$name"
    printf "  Category: %s | Complexity: %s\n" "$category" "$complexity"
    printf "  %s\n" "$description"
    echo ""
}

# Search modules
search_modules() {
    local query=$1
    print_header "Search Results for '$query'"

    local found=0
    for module in $(yq eval '.modules | keys | .[]' "$REGISTRY_FILE"); do
        local name=$(yq eval ".modules.${module}.name // \"\"" "$REGISTRY_FILE")
        local description=$(yq eval ".modules.${module}.description // \"\"" "$REGISTRY_FILE")
        local tags=$(yq eval ".modules.${module}.tags | join(\" \")" "$REGISTRY_FILE")

        # Case-insensitive search in name, description, and tags
        if echo "$name $description $tags" | grep -qi "$query"; then
            print_module_summary "$module"
            found=$((found + 1))
        fi
    done

    if [ $found -eq 0 ]; then
        echo -e "${YELLOW}No modules found matching '$query'${NC}"
        echo ""
        echo "Try searching by:"
        echo "  - Module name (e.g., vpc, eks, rds)"
        echo "  - Category (e.g., networking, containers)"
        echo "  - Feature (e.g., kubernetes, database)"
    else
        echo -e "${GREEN}Found $found module(s)${NC}"
    fi
}

# List modules
list_modules() {
    local category=$1

    if [ -n "$category" ]; then
        print_header "Modules in '$category'"

        for module in $(yq eval '.modules | keys | .[]' "$REGISTRY_FILE"); do
            local mod_category=$(yq eval ".modules.${module}.category // \"\"" "$REGISTRY_FILE")
            if [[ "$mod_category" == "$category"* ]]; then
                print_module_summary "$module"
            fi
        done
    else
        print_header "All Available Modules"

        # Group by category
        local categories=$(yq eval '[.modules[].category] | unique | .[]' "$REGISTRY_FILE" | sort)

        for cat in $categories; do
            echo -e "${BOLD}${CYAN}[$cat]${NC}"
            echo ""

            for module in $(yq eval '.modules | keys | .[]' "$REGISTRY_FILE"); do
                local mod_category=$(yq eval ".modules.${module}.category // \"\"" "$REGISTRY_FILE")
                if [ "$mod_category" == "$cat" ]; then
                    local name=$(yq eval ".modules.${module}.display_name // \"${module}\"" "$REGISTRY_FILE")
                    local maturity=$(yq eval ".modules.${module}.maturity // \"unknown\"" "$REGISTRY_FILE")

                    local maturity_color=$NC
                    case $maturity in
                        "production") maturity_color=$GREEN ;;
                        "stable") maturity_color=$BLUE ;;
                        "beta") maturity_color=$YELLOW ;;
                    esac

                    printf "  ${BOLD}%-20s${NC} %-30s ${maturity_color}[%s]${NC}\n" "$module" "$name" "$maturity"
                fi
            done
            echo ""
        done
    fi
}

# Show module info
show_info() {
    local module=$1

    if ! yq eval ".modules.${module}" "$REGISTRY_FILE" | grep -q "^name:"; then
        echo -e "${RED}Error: Module '$module' not found${NC}"
        exit 1
    fi

    print_header "Module: $module"

    echo -e "${BOLD}General Information${NC}"
    echo "-------------------"
    printf "Name:        %s\n" "$(yq eval ".modules.${module}.display_name" "$REGISTRY_FILE")"
    printf "Category:    %s\n" "$(yq eval ".modules.${module}.category" "$REGISTRY_FILE")"
    printf "Version:     %s\n" "$(yq eval ".modules.${module}.version" "$REGISTRY_FILE")"
    printf "Maturity:    %s\n" "$(yq eval ".modules.${module}.maturity" "$REGISTRY_FILE")"
    printf "Complexity:  %s\n" "$(yq eval ".modules.${module}.complexity" "$REGISTRY_FILE")"
    printf "Deploy Time: %s\n" "$(yq eval ".modules.${module}.deployment_time" "$REGISTRY_FILE")"
    echo ""

    echo -e "${BOLD}Description${NC}"
    echo "-----------"
    yq eval ".modules.${module}.description" "$REGISTRY_FILE"
    echo ""

    echo -e "${BOLD}Features${NC}"
    echo "--------"
    yq eval ".modules.${module}.features[]" "$REGISTRY_FILE" | while read feature; do
        echo "  - $feature"
    done
    echo ""

    echo -e "${BOLD}Cost Estimate${NC}"
    echo "-------------"
    printf "Minimum: %s\n" "$(yq eval ".modules.${module}.cost_estimate.minimum" "$REGISTRY_FILE")"
    printf "Typical: %s\n" "$(yq eval ".modules.${module}.cost_estimate.typical" "$REGISTRY_FILE")"
    printf "Maximum: %s\n" "$(yq eval ".modules.${module}.cost_estimate.maximum" "$REGISTRY_FILE")"
    echo ""

    echo -e "${BOLD}Dependencies${NC}"
    echo "------------"
    local deps=$(yq eval ".modules.${module}.dependencies | length" "$REGISTRY_FILE")
    if [ "$deps" -eq 0 ]; then
        echo "  None"
    else
        yq eval ".modules.${module}.dependencies[]" "$REGISTRY_FILE" | while read dep; do
            echo "  - $dep"
        done
    fi
    echo ""

    echo -e "${BOLD}Required By${NC}"
    echo "-----------"
    local dependents=$(yq eval ".modules.${module}.dependents | length" "$REGISTRY_FILE" 2>/dev/null || echo "0")
    if [ "$dependents" -eq 0 ] || [ "$dependents" == "null" ]; then
        echo "  None"
    else
        yq eval ".modules.${module}.dependents[]" "$REGISTRY_FILE" | while read dep; do
            echo "  - $dep"
        done
    fi
    echo ""

    echo -e "${BOLD}Tags${NC}"
    echo "----"
    yq eval ".modules.${module}.tags | join(\", \")" "$REGISTRY_FILE"
    echo ""
}

# Show dependencies
show_deps() {
    local module=$1

    print_header "Dependency Tree for '$module'"

    echo -e "${BOLD}Direct Dependencies:${NC}"
    local deps=$(yq eval ".modules.${module}.dependencies | length" "$REGISTRY_FILE")
    if [ "$deps" -eq 0 ]; then
        echo "  None"
    else
        yq eval ".modules.${module}.dependencies[]" "$REGISTRY_FILE" | while read dep; do
            local dep_name=$(yq eval ".modules.${dep}.display_name // \"${dep}\"" "$REGISTRY_FILE")
            echo -e "  ${GREEN}->$NC $dep ($dep_name)"

            # Show transitive dependencies
            local trans_deps=$(yq eval ".modules.${dep}.dependencies | length" "$REGISTRY_FILE" 2>/dev/null || echo "0")
            if [ "$trans_deps" -gt 0 ]; then
                yq eval ".modules.${dep}.dependencies[]" "$REGISTRY_FILE" 2>/dev/null | while read trans_dep; do
                    echo -e "      ${CYAN}->$NC $trans_dep"
                done
            fi
        done
    fi
    echo ""

    echo -e "${BOLD}Required By:${NC}"
    local dependents=$(yq eval ".modules.${module}.dependents | length" "$REGISTRY_FILE" 2>/dev/null || echo "0")
    if [ "$dependents" -eq 0 ] || [ "$dependents" == "null" ]; then
        echo "  None"
    else
        yq eval ".modules.${module}.dependents[]" "$REGISTRY_FILE" | while read dep; do
            local dep_name=$(yq eval ".modules.${dep}.display_name // \"${dep}\"" "$REGISTRY_FILE")
            echo -e "  ${YELLOW}<-$NC $dep ($dep_name)"
        done
    fi
}

# Show cost estimate
show_cost() {
    local module=$1

    print_header "Cost Estimate for '$module'"

    echo -e "${BOLD}Monthly Cost Range${NC}"
    echo "-------------------"
    printf "Minimum: ${GREEN}%s${NC}\n" "$(yq eval ".modules.${module}.cost_estimate.minimum" "$REGISTRY_FILE")"
    printf "Typical: ${YELLOW}%s${NC}\n" "$(yq eval ".modules.${module}.cost_estimate.typical" "$REGISTRY_FILE")"
    printf "Maximum: ${RED}%s${NC}\n" "$(yq eval ".modules.${module}.cost_estimate.maximum" "$REGISTRY_FILE")"
    echo ""

    echo -e "${BOLD}Cost Factors${NC}"
    echo "------------"
    yq eval ".modules.${module}.cost_estimate.factors[]" "$REGISTRY_FILE" 2>/dev/null | while read factor; do
        echo "  - $factor"
    done || echo "  No specific factors listed"
}

# Recommend modules
recommend_modules() {
    local use_case=$1

    print_header "Recommended Modules for '$use_case'"

    case $use_case in
        "web-app"|"webapp")
            echo "For a typical web application, consider:"
            echo ""
            echo -e "${BOLD}Core Infrastructure:${NC}"
            echo "  1. vpc           - Network foundation"
            echo "  2. securitygroup - Network security"
            echo "  3. iam           - Identity management"
            echo ""
            echo -e "${BOLD}Compute:${NC}"
            echo "  4. eks           - Kubernetes cluster"
            echo "  5. eks-addons    - Kubernetes addons"
            echo ""
            echo -e "${BOLD}Data:${NC}"
            echo "  6. rds           - Database"
            echo ""
            echo -e "${BOLD}Security:${NC}"
            echo "  7. acm           - SSL certificates"
            echo "  8. secretsmanager - Secrets storage"
            echo ""
            echo -e "${BOLD}Observability:${NC}"
            echo "  9. monitoring    - CloudWatch monitoring"
            echo ""
            echo -e "${GREEN}Suggested Blueprint: web-app-stack${NC}"
            ;;

        "api"|"rest-api"|"serverless")
            echo "For a serverless API, consider:"
            echo ""
            echo -e "${BOLD}API Layer:${NC}"
            echo "  1. apigateway    - API Gateway"
            echo ""
            echo -e "${BOLD}Compute:${NC}"
            echo "  2. lambda        - Serverless functions"
            echo ""
            echo -e "${BOLD}Security:${NC}"
            echo "  3. iam           - IAM roles"
            echo "  4. secretsmanager - Secrets"
            echo ""
            echo -e "${BOLD}Observability:${NC}"
            echo "  5. monitoring    - CloudWatch monitoring"
            echo ""
            echo -e "${GREEN}Suggested Blueprint: serverless-api-stack${NC}"
            ;;

        "microservices")
            echo "For a microservices platform, consider:"
            echo ""
            echo -e "${BOLD}Infrastructure:${NC}"
            echo "  1. vpc           - Network foundation"
            echo "  2. securitygroup - Network security"
            echo ""
            echo -e "${BOLD}Platform:${NC}"
            echo "  3. eks           - Kubernetes cluster"
            echo "  4. eks-addons    - Platform addons"
            echo "  5. apigateway    - API Gateway"
            echo ""
            echo -e "${BOLD}Data:${NC}"
            echo "  6. rds           - Databases"
            echo ""
            echo -e "${BOLD}Observability:${NC}"
            echo "  7. monitoring    - Full observability"
            echo ""
            echo -e "${GREEN}Suggested Blueprint: microservices-stack${NC}"
            ;;

        "data-pipeline"|"analytics")
            echo "For a data pipeline, consider:"
            echo ""
            echo -e "${BOLD}Suggested Blueprint: data-lake-stack${NC}"
            echo ""
            echo "Key components:"
            echo "  - S3 buckets for data zones"
            echo "  - Glue for ETL"
            echo "  - Athena for querying"
            ;;

        "streaming"|"real-time")
            echo "For real-time streaming, consider:"
            echo ""
            echo -e "${GREEN}Suggested Blueprint: streaming-pipeline-stack${NC}"
            echo ""
            echo "Key components:"
            echo "  - Kinesis for ingestion"
            echo "  - Lambda for processing"
            echo "  - OpenSearch for analytics"
            ;;

        "ml"|"machine-learning")
            echo "For machine learning, consider:"
            echo ""
            echo -e "${GREEN}Suggested Blueprint: ml-platform-stack${NC}"
            echo ""
            echo "Key components:"
            echo "  - SageMaker for training"
            echo "  - S3 for data storage"
            echo "  - MLflow for experiment tracking"
            ;;

        "saas"|"multi-tenant")
            echo "For a SaaS platform, consider:"
            echo ""
            echo -e "${GREEN}Suggested Blueprint: saas-multi-tenant-stack${NC}"
            echo ""
            echo "Key components:"
            echo "  - EKS for compute"
            echo "  - RDS for tenant databases"
            echo "  - Cognito for authentication"
            ;;

        *)
            echo -e "${YELLOW}Unknown use case: $use_case${NC}"
            echo ""
            echo "Available use cases:"
            echo "  - web-app"
            echo "  - api / serverless"
            echo "  - microservices"
            echo "  - data-pipeline / analytics"
            echo "  - streaming / real-time"
            echo "  - ml / machine-learning"
            echo "  - saas / multi-tenant"
            ;;
    esac
}

# Print usage
print_usage() {
    echo "Module Search and Discovery Tool"
    echo ""
    echo "Usage: $0 <command> [arguments]"
    echo ""
    echo "Commands:"
    echo "  search <query>      Search modules by name, description, or tags"
    echo "  list [category]     List all modules or modules in a category"
    echo "  info <module>       Show detailed module information"
    echo "  deps <module>       Show module dependencies"
    echo "  cost <module>       Show module cost estimate"
    echo "  recommend <case>    Recommend modules for a use case"
    echo ""
    echo "Examples:"
    echo "  $0 search vpc"
    echo "  $0 list foundations/networking"
    echo "  $0 info eks"
    echo "  $0 deps rds"
    echo "  $0 cost eks"
    echo "  $0 recommend web-app"
}

# Main
main() {
    check_requirements

    local command=$1
    shift

    case $command in
        "search")
            search_modules "$1"
            ;;
        "list")
            list_modules "$1"
            ;;
        "info")
            show_info "$1"
            ;;
        "deps")
            show_deps "$1"
            ;;
        "cost")
            show_cost "$1"
            ;;
        "recommend")
            recommend_modules "$1"
            ;;
        "help"|"--help"|"-h"|"")
            print_usage
            ;;
        *)
            echo -e "${RED}Unknown command: $command${NC}"
            print_usage
            exit 1
            ;;
    esac
}

main "$@"
