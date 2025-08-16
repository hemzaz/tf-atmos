# =============================================================================
# Terraform/Atmos Infrastructure Developer Experience Makefile
# =============================================================================
# This Makefile provides shortcuts for common development tasks
# Run 'make help' to see all available commands

.PHONY: help setup clean validate lint plan apply destroy status dev-start dev-stop dev-logs
.DEFAULT_GOAL := help

# =============================================================================
# Configuration
# =============================================================================

# Default values - can be overridden via environment or command line
TENANT ?= fnx
ACCOUNT ?= dev
ENVIRONMENT ?= testenv-01
REGION ?= eu-west-2

# Derived values
STACK := orgs/$(TENANT)/$(ACCOUNT)/$(REGION)/$(ENVIRONMENT)
FRIENDLY_STACK := $(TENANT)-$(ENVIRONMENT)-$(ACCOUNT)

# Colors for pretty output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
PURPLE := \033[0;35m
CYAN := \033[0;36m
WHITE := \033[1;37m
NC := \033[0m # No Color

# =============================================================================
# Help and Information
# =============================================================================

help: ## Show this help message
	@echo "$(CYAN)Terraform/Atmos Infrastructure Makefile$(NC)"
	@echo "$(WHITE)========================================$(NC)"
	@echo
	@echo "$(WHITE)Current Configuration:$(NC)"
	@echo "  TENANT:      $(GREEN)$(TENANT)$(NC)"
	@echo "  ACCOUNT:     $(GREEN)$(ACCOUNT)$(NC)"
	@echo "  ENVIRONMENT: $(GREEN)$(ENVIRONMENT)$(NC)"
	@echo "  REGION:      $(GREEN)$(REGION)$(NC)"
	@echo "  STACK:       $(GREEN)$(FRIENDLY_STACK)$(NC)"
	@echo
	@echo "$(WHITE)Available Commands:$(NC)"
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*?##/ { printf "  $(CYAN)%-15s$(NC) %s\n", $$1, $$2 }' $(MAKEFILE_LIST) | sort
	@echo
	@echo "$(WHITE)Examples:$(NC)"
	@echo "  make status                           # Show current stack status"
	@echo "  make validate                        # Validate all configurations"
	@echo "  make plan TENANT=prod ACCOUNT=main   # Plan with different params"
	@echo "  make apply ENVIRONMENT=staging       # Apply to staging environment"
	@echo
	@echo "$(WHITE)Development:$(NC)"
	@echo "  make dev-start                       # Start development environment"
	@echo "  make dev-logs                        # View development logs"
	@echo "  make onboard                         # Quick environment onboarding"

info: ## Show detailed system and stack information
	@echo "$(WHITE)System Information:$(NC)"
	@echo "================================"
	@command -v atmos >/dev/null 2>&1 && echo "✅ Atmos: $$(atmos version)" || echo "❌ Atmos: Not installed"
	@command -v terraform >/dev/null 2>&1 && echo "✅ Terraform: $$(terraform version | head -1)" || echo "❌ Terraform: Not installed"
	@command -v docker >/dev/null 2>&1 && echo "✅ Docker: $$(docker version --format '{{.Client.Version}}')" || echo "❌ Docker: Not installed"
	@command -v gaia >/dev/null 2>&1 && echo "✅ Gaia CLI: $$(gaia version | grep 'Gaia CLI' | head -1)" || echo "⚠️  Gaia CLI: Not installed (optional)"
	@echo
	@echo "$(WHITE)Available Stacks:$(NC)"
	@echo "===================="
	@./scripts/list_stacks.sh || atmos list stacks
	@echo
	@echo "$(WHITE)Current Stack Components:$(NC)"
	@echo "=========================="
	@atmos list components -s "$(STACK)" 2>/dev/null || echo "No components found for $(FRIENDLY_STACK)"

# =============================================================================
# Core Infrastructure Commands
# =============================================================================

validate: ## Validate all Terraform configurations
	@echo "$(BLUE)Validating configurations for $(FRIENDLY_STACK)...$(NC)"
	@atmos workflow validate tenant=$(TENANT) account=$(ACCOUNT) environment=$(ENVIRONMENT)

lint: ## Lint and format all code
	@echo "$(BLUE)Linting and formatting code...$(NC)"
	@atmos workflow lint

plan: ## Plan infrastructure changes
	@echo "$(BLUE)Planning infrastructure changes for $(FRIENDLY_STACK)...$(NC)"
	@atmos workflow plan-environment tenant=$(TENANT) account=$(ACCOUNT) environment=$(ENVIRONMENT)

apply: ## Apply infrastructure changes (with confirmation)
	@echo "$(YELLOW)⚠️  This will apply changes to $(FRIENDLY_STACK)!$(NC)"
	@read -p "Are you sure? (y/N) " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		echo "$(BLUE)Applying infrastructure changes...$(NC)"; \
		atmos workflow apply-environment tenant=$(TENANT) account=$(ACCOUNT) environment=$(ENVIRONMENT); \
	else \
		echo "$(YELLOW)Apply cancelled.$(NC)"; \
	fi

destroy: ## Destroy infrastructure (with double confirmation)
	@echo "$(RED)⚠️  DANGER: This will DESTROY all infrastructure in $(FRIENDLY_STACK)!$(NC)"
	@read -p "Type '$(FRIENDLY_STACK)' to confirm: " confirm; \
	if [ "$$confirm" = "$(FRIENDLY_STACK)" ]; then \
		echo "$(RED)Final confirmation - are you absolutely sure? (y/N)$(NC)"; \
		read -p "" -n 1 -r; \
		echo; \
		if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
			echo "$(RED)Destroying infrastructure...$(NC)"; \
			atmos workflow destroy-environment tenant=$(TENANT) account=$(ACCOUNT) environment=$(ENVIRONMENT); \
		else \
			echo "$(GREEN)Destroy cancelled.$(NC)"; \
		fi; \
	else \
		echo "$(GREEN)Destroy cancelled - confirmation didn't match.$(NC)"; \
	fi

status: ## Show current infrastructure status
	@echo "$(WHITE)Infrastructure Status for $(FRIENDLY_STACK)$(NC)"
	@echo "================================================"
	@echo "$(WHITE)Stack:$(NC) $(STACK)"
	@echo "$(WHITE)Components:$(NC)"
	@atmos list components -s "$(STACK)" 2>/dev/null || echo "  No components configured"
	@echo
	@echo "$(WHITE)Recent Workflow Runs:$(NC)"
	@echo "====================="
	@ls -la logs/ 2>/dev/null | head -10 || echo "  No workflow logs found"

drift: ## Check for configuration drift
	@echo "$(BLUE)Checking for configuration drift...$(NC)"
	@atmos workflow drift-detection

# =============================================================================
# Component-Specific Commands
# =============================================================================

plan-vpc: ## Plan VPC changes
	@echo "$(BLUE)Planning VPC changes...$(NC)"
	@atmos terraform plan vpc -s "$(STACK)"

apply-vpc: ## Apply VPC changes
	@echo "$(BLUE)Applying VPC changes...$(NC)"
	@atmos terraform apply vpc -s "$(STACK)"

plan-eks: ## Plan EKS changes
	@echo "$(BLUE)Planning EKS changes...$(NC)"
	@atmos terraform plan eks -s "$(STACK)"

apply-eks: ## Apply EKS changes
	@echo "$(BLUE)Applying EKS changes...$(NC)"
	@atmos terraform apply eks -s "$(STACK)"

plan-component: ## Plan specific component (usage: make plan-component COMPONENT=vpc)
	@if [ -z "$(COMPONENT)" ]; then \
		echo "$(RED)Error: COMPONENT variable is required$(NC)"; \
		echo "Usage: make plan-component COMPONENT=vpc"; \
		exit 1; \
	fi
	@echo "$(BLUE)Planning $(COMPONENT) changes...$(NC)"
	@atmos terraform plan $(COMPONENT) -s "$(STACK)"

apply-component: ## Apply specific component (usage: make apply-component COMPONENT=vpc)
	@if [ -z "$(COMPONENT)" ]; then \
		echo "$(RED)Error: COMPONENT variable is required$(NC)"; \
		echo "Usage: make apply-component COMPONENT=vpc"; \
		exit 1; \
	fi
	@echo "$(BLUE)Applying $(COMPONENT) changes...$(NC)"
	@atmos terraform apply $(COMPONENT) -s "$(STACK)"

# =============================================================================
# Development Environment Commands
# =============================================================================

setup: ## Setup development environment
	@echo "$(BLUE)Setting up development environment...$(NC)"
	@./scripts/dev-setup.sh
	@$(MAKE) install-gaia

install-gaia: ## Install/upgrade Gaia CLI tool
	@echo "$(BLUE)Installing Gaia CLI...$(NC)"
	@cd gaia && pip install -e .
	@echo "$(GREEN)✅ Gaia CLI installed. Run 'gaia --help' to get started.$(NC)"

dev-start: ## Start development environment with Docker Compose
	@echo "$(BLUE)Starting development environment...$(NC)"
	@./scripts/start-dev.sh

dev-stop: ## Stop development environment
	@echo "$(BLUE)Stopping development environment...$(NC)"
	@./scripts/stop-dev.sh

dev-logs: ## View development environment logs
	@echo "$(BLUE)Following development logs...$(NC)"
	@./scripts/logs-dev.sh

dev-reset: ## Reset development environment (removes all data)
	@echo "$(RED)⚠️  This will remove all development data!$(NC)"
	@./scripts/reset-dev.sh

# =============================================================================
# Environment Management
# =============================================================================

onboard: ## Quick environment onboarding with defaults
	@echo "$(BLUE)Onboarding environment $(FRIENDLY_STACK)...$(NC)"
	@echo "Using default VPC CIDR: 10.0.0.0/16"
	@atmos workflow onboard-environment tenant=$(TENANT) account=$(ACCOUNT) environment=$(ENVIRONMENT) vpc_cidr=10.0.0.0/16

onboard-custom: ## Custom environment onboarding (usage: make onboard-custom VPC_CIDR=10.1.0.0/16)
	@if [ -z "$(VPC_CIDR)" ]; then \
		echo "$(RED)Error: VPC_CIDR variable is required$(NC)"; \
		echo "Usage: make onboard-custom VPC_CIDR=10.1.0.0/16"; \
		exit 1; \
	fi
	@echo "$(BLUE)Onboarding environment $(FRIENDLY_STACK) with VPC CIDR $(VPC_CIDR)...$(NC)"
	@atmos workflow onboard-environment tenant=$(TENANT) account=$(ACCOUNT) environment=$(ENVIRONMENT) vpc_cidr=$(VPC_CIDR)

list-stacks: ## List all available stacks
	@echo "$(WHITE)Available Stacks:$(NC)"
	@echo "=================="
	@./scripts/list_stacks.sh

# =============================================================================
# Testing and Quality
# =============================================================================

test: ## Run all tests and validations
	@echo "$(BLUE)Running comprehensive tests...$(NC)"
	@$(MAKE) lint
	@$(MAKE) validate
	@echo "$(GREEN)✅ All tests passed!$(NC)"

check-security: ## Run security checks
	@echo "$(BLUE)Running security checks...$(NC)"
	@echo "⚠️  Security scanning not yet implemented"
	@echo "TODO: Integrate with checkov, tfsec, or similar tools"

check-costs: ## Estimate infrastructure costs
	@echo "$(BLUE)Checking estimated costs...$(NC)"
	@echo "⚠️  Cost estimation not yet implemented"
	@echo "TODO: Integrate with infracost or similar tools"

# =============================================================================
# Utilities
# =============================================================================

clean: ## Clean temporary files and caches
	@echo "$(BLUE)Cleaning temporary files...$(NC)"
	@find . -name "*.tfplan" -delete
	@find . -name ".terraform.lock.hcl" -delete 2>/dev/null || true
	@find . -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null || true
	@find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
	@find . -name "*.pyc" -delete 2>/dev/null || true
	@echo "$(GREEN)✅ Cleanup complete$(NC)"

update-docs: ## Update and migrate documentation
	@echo "$(BLUE)Updating documentation...$(NC)"
	@./scripts/migrate_docs.sh

backup-state: ## Backup Terraform state (for disaster recovery)
	@echo "$(BLUE)Creating state backup...$(NC)"
	@echo "⚠️  State backup not yet implemented"
	@echo "TODO: Implement automated state backup"

doctor: ## Run system diagnostics
	@echo "$(WHITE)System Diagnostics$(NC)"
	@echo "=================="
	@$(MAKE) info
	@echo
	@echo "$(WHITE)Configuration Checks:$(NC)"
	@echo "====================="
	@test -f atmos.yaml && echo "✅ atmos.yaml found" || echo "❌ atmos.yaml missing"
	@test -d components/terraform && echo "✅ Terraform components directory found" || echo "❌ Terraform components directory missing"
	@test -d stacks && echo "✅ Stacks directory found" || echo "❌ Stacks directory missing"
	@test -d workflows && echo "✅ Workflows directory found" || echo "❌ Workflows directory missing"
	@echo
	@echo "$(WHITE)Stack Validation:$(NC)"
	@echo "=================="
	@atmos describe stacks -s "$(STACK)" >/dev/null 2>&1 && echo "✅ Current stack configuration is valid" || echo "❌ Current stack configuration has issues"

# =============================================================================
# Quick Aliases for Frequent Tasks
# =============================================================================

v: validate ## Alias for validate
l: lint ## Alias for lint
p: plan ## Alias for plan
a: apply ## Alias for apply
s: status ## Alias for status
i: info ## Alias for info
h: help ## Alias for help

# =============================================================================
# Environment-Specific Shortcuts
# =============================================================================

dev: ## Switch to development environment
	@$(MAKE) TENANT=fnx ACCOUNT=dev ENVIRONMENT=testenv-01 status

staging: ## Switch to staging environment  
	@$(MAKE) TENANT=fnx ACCOUNT=staging ENVIRONMENT=staging-01 status

prod: ## Switch to production environment
	@$(MAKE) TENANT=fnx ACCOUNT=prod ENVIRONMENT=production status

# =============================================================================
# Advanced Operations
# =============================================================================

import-resource: ## Import existing resource into Terraform state
	@echo "$(BLUE)Starting resource import workflow...$(NC)"
	@atmos workflow import

rotate-certs: ## Rotate SSL certificates
	@echo "$(BLUE)Rotating SSL certificates...$(NC)"
	@atmos workflow rotate-certificate

state-ops: ## Perform state operations
	@echo "$(BLUE)Starting state operations workflow...$(NC)"
	@atmos workflow state-operations

# =============================================================================
# Debugging and Troubleshooting
# =============================================================================

debug-stack: ## Debug current stack configuration
	@echo "$(WHITE)Stack Debug Information$(NC)"
	@echo "========================"
	@echo "Stack Name: $(STACK)"
	@echo "Friendly Name: $(FRIENDLY_STACK)"
	@echo
	@echo "$(WHITE)Stack Description:$(NC)"
	@atmos describe stacks -s "$(STACK)" || echo "Failed to describe stack"
	@echo
	@echo "$(WHITE)Stack Components:$(NC)"
	@atmos list components -s "$(STACK)" || echo "Failed to list components"

debug-env: ## Debug environment variables and configuration
	@echo "$(WHITE)Environment Debug Information$(NC)"
	@echo "============================="
	@echo "TENANT: $(TENANT)"
	@echo "ACCOUNT: $(ACCOUNT)" 
	@echo "ENVIRONMENT: $(ENVIRONMENT)"
	@echo "REGION: $(REGION)"
	@echo "STACK: $(STACK)"
	@echo "FRIENDLY_STACK: $(FRIENDLY_STACK)"
	@echo
	@echo "$(WHITE)Working Directory:$(NC)"
	@pwd
	@echo
	@echo "$(WHITE)Atmos Configuration:$(NC)"
	@test -f atmos.yaml && head -20 atmos.yaml || echo "atmos.yaml not found"

# =============================================================================
# Performance and Optimization
# =============================================================================

benchmark: ## Run performance benchmarks
	@echo "$(BLUE)Running infrastructure benchmarks...$(NC)"
	@echo "⚠️  Benchmarking not yet implemented"
	@echo "TODO: Add performance benchmarks for common operations"

profile: ## Profile resource usage and costs
	@echo "$(BLUE)Profiling resource usage...$(NC)"
	@echo "⚠️  Resource profiling not yet implemented"
	@echo "TODO: Add resource usage analysis"

# =============================================================================
# Developer Experience and Feedback
# =============================================================================

feedback: ## Collect developer experience feedback
	@echo "$(BLUE)Collecting developer experience feedback...$(NC)"
	@./scripts/collect-dx-feedback.sh interactive

dx-metrics: ## Collect DX metrics without interactive prompts
	@echo "$(BLUE)Collecting DX metrics...$(NC)"
	@./scripts/collect-dx-feedback.sh metrics-only

dx-summary: ## Show DX metrics summary
	@echo "$(BLUE)Developer Experience Summary:$(NC)"
	@./scripts/collect-dx-feedback.sh summary

dx-improve: ## Get personalized DX improvement recommendations
	@echo "$(BLUE)Analyzing your development patterns...$(NC)"
	@if [ -f .dx-metrics/dx-summary.json ]; then \
		echo "$(WHITE)Based on your usage patterns, here are some recommendations:$(NC)"; \
		jq -r '.summary.improvement_areas[]' .dx-metrics/dx-summary.json | sed 's/^/  • /'; \
	else \
		echo "$(YELLOW)No DX data found. Run 'make feedback' to collect data first.$(NC)"; \
	fi