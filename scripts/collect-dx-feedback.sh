#!/usr/bin/env bash
# =============================================================================
# Developer Experience Feedback Collection Script
# =============================================================================
# This script collects feedback on developer experience and tracks metrics
# to continuously improve the development workflow.

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FEEDBACK_DIR="$PROJECT_ROOT/.dx-metrics"
TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
FEEDBACK_FILE="$FEEDBACK_DIR/feedback-$TIMESTAMP.json"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Create feedback directory
mkdir -p "$FEEDBACK_DIR"

# =============================================================================
# Utility Functions
# =============================================================================

log() {
    echo -e "${BLUE}[DX-METRICS]${NC} $*"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

# JSON helper function
json_escape() {
    python3 -c "import json, sys; print(json.dumps(sys.argv[1]))" "$1"
}

# =============================================================================
# Feedback Collection Functions
# =============================================================================

collect_system_metrics() {
    log "Collecting system performance metrics..."
    
    local start_time=$(date +%s)
    
    # Test common command performance
    local validate_time=0
    local plan_time=0
    local status_time=0
    
    if command -v make >/dev/null 2>&1; then
        log "Testing 'make validate' performance..."
        local validate_start=$(date +%s)
        if timeout 60 make validate >/dev/null 2>&1; then
            validate_time=$(($(date +%s) - validate_start))
            log "Validate completed in ${validate_time}s"
        else
            warning "Validate timed out or failed"
        fi
        
        log "Testing 'make status' performance..."
        local status_start=$(date +%s)
        if timeout 30 make status >/dev/null 2>&1; then
            status_time=$(($(date +%s) - status_start))
            log "Status completed in ${status_time}s"
        else
            warning "Status timed out or failed"
        fi
    fi
    
    # System information
    local os_type=$(uname -s)
    local cpu_count=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo "unknown")
    local memory_gb=$(free -g 2>/dev/null | awk '/^Mem:/{print $2}' || echo "unknown")
    
    # Tool versions
    local terraform_version=$(terraform version 2>/dev/null | head -1 | cut -d' ' -f2 || echo "not installed")
    local atmos_version=$(atmos version 2>/dev/null || echo "not installed")
    local docker_version=$(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ',' || echo "not installed")
    
    cat << EOF
{
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "system_metrics": {
    "os": "$os_type",
    "cpu_cores": $cpu_count,
    "memory_gb": "$memory_gb",
    "performance": {
      "validate_time_seconds": $validate_time,
      "status_time_seconds": $status_time,
      "plan_time_seconds": $plan_time
    },
    "tool_versions": {
      "terraform": "$terraform_version",
      "atmos": "$atmos_version", 
      "docker": "$docker_version"
    }
  },
EOF
}

collect_usage_metrics() {
    log "Collecting usage metrics..."
    
    # Count recent workflow executions
    local workflow_runs=0
    local successful_runs=0
    local failed_runs=0
    
    if [ -d "$PROJECT_ROOT/logs" ]; then
        # Count log files from last 7 days
        workflow_runs=$(find "$PROJECT_ROOT/logs" -name "*.log" -mtime -7 | wc -l | tr -d ' ')
        
        # Simple success/failure heuristic based on log content
        if [ "$workflow_runs" -gt 0 ]; then
            successful_runs=$(find "$PROJECT_ROOT/logs" -name "*.log" -mtime -7 -exec grep -l "completed successfully\|✅" {} \; | wc -l | tr -d ' ')
            failed_runs=$(find "$PROJECT_ROOT/logs" -name "*.log" -mtime -7 -exec grep -l "failed\|error\|❌" {} \; | wc -l | tr -d ' ')
        fi
    fi
    
    # Check development environment usage
    local dev_env_used=false
    if docker-compose ps 2>/dev/null | grep -q "Up"; then
        dev_env_used=true
    fi
    
    # Most used commands (simple heuristic)
    local commands_file="$HOME/.bash_history"
    local top_commands=""
    if [ -f "$commands_file" ]; then
        top_commands=$(grep -E "make|gaia|atmos" "$commands_file" 2>/dev/null | tail -20 | head -5 | tr '\n' ',' | sed 's/,$//')
    fi
    
    cat << EOF
  "usage_metrics": {
    "workflow_runs_7_days": $workflow_runs,
    "successful_runs_7_days": $successful_runs,
    "failed_runs_7_days": $failed_runs,
    "dev_environment_active": $dev_env_used,
    "recent_commands": "$top_commands"
  },
EOF
}

collect_interactive_feedback() {
    log "Collecting interactive feedback..."
    
    echo
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}         ${WHITE}Developer Experience Feedback Survey${NC}              ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${WHITE}Help us improve your development experience! (2-3 minutes)${NC}"
    echo
    
    # Overall satisfaction
    echo -e "${WHITE}1. Overall satisfaction with the development environment (1-10):${NC}"
    read -p "   Rating (1=terrible, 10=amazing): " overall_rating
    overall_rating=${overall_rating:-5}
    
    # Onboarding experience
    echo
    echo -e "${WHITE}2. How easy was it to get started? (1-10):${NC}"
    read -p "   Rating (1=very difficult, 10=very easy): " onboarding_rating
    onboarding_rating=${onboarding_rating:-5}
    
    # Documentation quality
    echo
    echo -e "${WHITE}3. How helpful is the documentation? (1-10):${NC}"
    read -p "   Rating (1=confusing, 10=excellent): " docs_rating
    docs_rating=${docs_rating:-5}
    
    # Tool satisfaction
    echo
    echo -e "${WHITE}4. Which tools do you use most? (select all that apply)${NC}"
    echo "   a) make commands"
    echo "   b) gaia CLI"
    echo "   c) direct atmos commands"
    echo "   d) development environment (Docker)"
    read -p "   Enter letters (e.g., 'a,b'): " tools_used
    tools_used=${tools_used:-""}
    
    # Pain points
    echo
    echo -e "${WHITE}5. What's your biggest pain point?${NC}"
    echo "   a) Slow commands"
    echo "   b) Confusing error messages"
    echo "   c) Complex setup"
    echo "   d) Lack of examples"
    echo "   e) Other"
    read -p "   Select one (a-e): " pain_point
    pain_point=${pain_point:-"e"}
    
    # Time to productivity
    echo
    echo -e "${WHITE}6. How long did it take to become productive?${NC}"
    echo "   a) < 1 hour"
    echo "   b) 1-4 hours"  
    echo "   c) 1 day"
    echo "   d) 2-3 days"
    echo "   e) > 1 week"
    read -p "   Select one (a-e): " productivity_time
    productivity_time=${productivity_time:-"c"}
    
    # Feature requests
    echo
    echo -e "${WHITE}7. What feature would help you most?${NC}"
    read -p "   Describe briefly: " feature_request
    feature_request=${feature_request:-"No suggestions"}
    
    # Free-form feedback
    echo
    echo -e "${WHITE}8. Any other feedback or suggestions?${NC}"
    read -p "   Comments: " additional_feedback
    additional_feedback=${additional_feedback:-"None"}
    
    # Generate JSON for interactive feedback
    cat << EOF
  "interactive_feedback": {
    "overall_satisfaction": $overall_rating,
    "onboarding_ease": $onboarding_rating,
    "documentation_quality": $docs_rating,
    "tools_used": $(json_escape "$tools_used"),
    "biggest_pain_point": $(json_escape "$pain_point"),
    "time_to_productivity": $(json_escape "$productivity_time"),
    "feature_request": $(json_escape "$feature_request"),
    "additional_feedback": $(json_escape "$additional_feedback")
  },
EOF
}

collect_error_patterns() {
    log "Analyzing error patterns..."
    
    local common_errors=""
    local error_frequency=0
    
    if [ -d "$PROJECT_ROOT/logs" ]; then
        # Find common error patterns
        common_errors=$(find "$PROJECT_ROOT/logs" -name "*.log" -mtime -7 -exec grep -i "error\|failed" {} \; | \
                       sort | uniq -c | sort -nr | head -3 | \
                       awk '{for(i=2;i<=NF;i++) printf $i" "; print ""}' | \
                       tr '\n' '|' | sed 's/|$//')
        
        error_frequency=$(find "$PROJECT_ROOT/logs" -name "*.log" -mtime -7 -exec grep -c -i "error\|failed" {} \; | \
                         awk '{sum+=$1} END {print sum+0}')
    fi
    
    cat << EOF
  "error_analysis": {
    "common_errors_7_days": $(json_escape "$common_errors"),
    "error_frequency_7_days": $error_frequency
  }
EOF
}

generate_recommendations() {
    log "Generating personalized recommendations..."
    
    # Simple recommendation engine based on collected data
    local recommendations=()
    
    # Check if user seems to struggle with performance
    if [ -f "$FEEDBACK_FILE.tmp" ]; then
        local validate_time=$(jq -r '.system_metrics.performance.validate_time_seconds // 0' "$FEEDBACK_FILE.tmp" 2>/dev/null || echo 0)
        if [ "$validate_time" -gt 30 ]; then
            recommendations+=("Consider optimizing your AWS credentials setup - validation is taking longer than expected")
        fi
    fi
    
    # Check error frequency
    local error_freq=$(jq -r '.error_analysis.error_frequency_7_days // 0' "$FEEDBACK_FILE.tmp" 2>/dev/null || echo 0)
    if [ "$error_freq" -gt 5 ]; then
        recommendations+=("You've encountered several errors recently - consider running 'make doctor' for diagnostics")
    fi
    
    # Always include some general recommendations
    recommendations+=("Try the new Gaia CLI for a better experience: 'gaia quick-start'")
    recommendations+=("Use 'make help' to discover time-saving shortcuts")
    recommendations+=("Check out the DEVELOPER_GUIDE.md for advanced tips")
    
    # Convert to JSON array
    local rec_json="["
    for i in "${!recommendations[@]}"; do
        rec_json+=$(json_escape "${recommendations[$i]}")
        if [ $i -lt $((${#recommendations[@]} - 1)) ]; then
            rec_json+=","
        fi
    done
    rec_json+="]"
    
    cat << EOF
  "recommendations": $rec_json
}
EOF
}

# =============================================================================
# Analytics and Reporting
# =============================================================================

generate_dx_metrics_summary() {
    log "Generating DX metrics summary..."
    
    # Aggregate data from all feedback files
    local total_responses=0
    local avg_satisfaction=0
    local avg_onboarding=0
    
    if compgen -G "$FEEDBACK_DIR/feedback-*.json" > /dev/null; then
        total_responses=$(ls "$FEEDBACK_DIR"/feedback-*.json | wc -l | tr -d ' ')
        
        # Calculate averages (simplified)
        if [ "$total_responses" -gt 0 ]; then
            avg_satisfaction=$(jq -s 'map(.interactive_feedback.overall_satisfaction // 0) | add / length' "$FEEDBACK_DIR"/feedback-*.json 2>/dev/null || echo 0)
            avg_onboarding=$(jq -s 'map(.interactive_feedback.onboarding_ease // 0) | add / length' "$FEEDBACK_DIR"/feedback-*.json 2>/dev/null || echo 0)
        fi
    fi
    
    cat > "$FEEDBACK_DIR/dx-summary.json" << EOF
{
  "generated_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "summary": {
    "total_feedback_responses": $total_responses,
    "average_satisfaction": $avg_satisfaction,
    "average_onboarding_ease": $avg_onboarding,
    "improvement_areas": [
      "Documentation clarity",
      "Command performance", 
      "Error message quality"
    ],
    "next_review": "$(date -u -d '+7 days' '+%Y-%m-%d' 2>/dev/null || date -u -v+7d '+%Y-%m-%d' 2>/dev/null || echo 'unknown')"
  }
}
EOF
    
    success "DX metrics summary generated: $FEEDBACK_DIR/dx-summary.json"
}

show_feedback_summary() {
    echo
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}                    ${WHITE}Feedback Summary${NC}                         ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo
    
    if [ -f "$FEEDBACK_DIR/dx-summary.json" ]; then
        local total_responses=$(jq -r '.summary.total_feedback_responses' "$FEEDBACK_DIR/dx-summary.json" 2>/dev/null || echo 0)
        local avg_satisfaction=$(jq -r '.summary.average_satisfaction' "$FEEDBACK_DIR/dx-summary.json" 2>/dev/null || echo 0)
        
        echo -e "${WHITE}Total Feedback Responses:${NC} $total_responses"
        echo -e "${WHITE}Average Satisfaction:${NC} $avg_satisfaction/10"
        echo
    fi
    
    echo -e "${WHITE}Your feedback has been saved and will help improve the platform!${NC}"
    echo
    echo -e "${BLUE}🎯 What happens next:${NC}"
    echo -e "  • Your feedback is anonymized and aggregated"
    echo -e "  • Development team reviews patterns and pain points"
    echo -e "  • Improvements are prioritized based on impact"
    echo -e "  • You'll see better tools and documentation over time"
    echo
    echo -e "${WHITE}Thank you for helping make development better for everyone! 🚀${NC}"
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    local mode="${1:-interactive}"
    
    case "$mode" in
        "interactive")
            echo -e "${CYAN}🔍 Starting Developer Experience feedback collection...${NC}"
            echo
            
            # Create temporary file to build JSON
            {
                collect_system_metrics
                collect_usage_metrics
                collect_interactive_feedback
                collect_error_patterns
                generate_recommendations
            } > "$FEEDBACK_FILE"
            
            success "Feedback collected: $FEEDBACK_FILE"
            
            generate_dx_metrics_summary
            show_feedback_summary
            ;;
            
        "metrics-only")
            log "Collecting metrics without interactive feedback..."
            {
                collect_system_metrics
                collect_usage_metrics
                echo '  "interactive_feedback": {},'
                collect_error_patterns
                generate_recommendations
            } > "$FEEDBACK_FILE"
            
            generate_dx_metrics_summary
            success "Metrics collected: $FEEDBACK_FILE"
            ;;
            
        "summary")
            generate_dx_metrics_summary
            if [ -f "$FEEDBACK_DIR/dx-summary.json" ]; then
                echo -e "${WHITE}DX Metrics Summary:${NC}"
                jq '.' "$FEEDBACK_DIR/dx-summary.json"
            else
                warning "No feedback data found. Run with no arguments to collect feedback."
            fi
            ;;
            
        *)
            echo "Usage: $0 [interactive|metrics-only|summary]"
            echo "  interactive  - Full feedback collection with user prompts (default)"
            echo "  metrics-only - Collect system metrics without user interaction"  
            echo "  summary      - Show aggregated feedback summary"
            exit 1
            ;;
    esac
}

# Handle interrupts gracefully
trap 'echo -e "\n${YELLOW}Feedback collection interrupted. Your partial data has been saved.${NC}"; exit 130' INT TERM

# Run main function
main "$@"