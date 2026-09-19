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

# Default values - can be overridden via environment or command line.
# Stack names follow atmos.yaml name_template: <tenant>-<stage>-<environment>
# (fnx-dev-testenv-01, fnx-staging-staging-01, fnx-prod-production).
# ACCOUNT is accepted as an alias for STAGE.
TENANT ?= fnx
STAGE ?= $(or $(ACCOUNT),dev)
ENVIRONMENT ?= testenv-01
REGION ?= eu-west-2

# Derived values (STACK can also be passed directly: make plan STACK=fnx-prod-production)
STACK ?= $(TENANT)-$(STAGE)-$(ENVIRONMENT)

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
	@echo "  STAGE:       $(GREEN)$(STAGE)$(NC)"
	@echo "  ENVIRONMENT: $(GREEN)$(ENVIRONMENT)$(NC)"
	@echo "  REGION:      $(GREEN)$(REGION)$(NC)"
	@echo "  STACK:       $(GREEN)$(STACK)$(NC)"
	@echo
	@echo "$(WHITE)Available Commands:$(NC)"
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*?##/ { printf "  $(CYAN)%-15s$(NC) %s\n", $$1, $$2 }' $(MAKEFILE_LIST) | sort
	@echo
	@echo "$(WHITE)Power User Features:$(NC)"
	@echo "  $(YELLOW)Workflows:$(NC)      atmos list workflows $(GREEN)# All Atmos workflows$(NC)"
	@echo "  $(YELLOW)Watch Mode:$(NC)     make watch-validate $(GREEN)# Continuous validation$(NC)"
	@echo "  $(YELLOW)Batch Ops:$(NC)      make validate-all  $(GREEN)# Validate all stacks$(NC)"
	@echo
	@echo "$(WHITE)Quick Examples:$(NC)"
	@echo "  $(GREEN)make validate STAGE=prod ENVIRONMENT=production$(NC)"
	@echo "  $(GREEN)make plan-component COMPONENT=vpc/main$(NC)"
	@echo "  $(GREEN)make api-validate-stack STACK=fnx-dev-testenv-01$(NC)"

# =============================================================================
# API-Style Shortcuts (atmos wrappers)
# =============================================================================

api-docs: ## List Atmos workflows and their descriptions
	@atmos list workflows

api-health: ## Check that Atmos and its configuration load
	@atmos version && atmos validate config

api-status: ## Show components of the current stack
	@atmos list components -s "$(STACK)"

api-list-stacks: ## List all stacks
	@atmos list stacks

api-validate-stack: ## Validate a specific stack (usage: make api-validate-stack STACK=fnx-dev-testenv-01)
	@echo "$(CYAN)✅ Validating stack: $(STACK)$(NC)"
	@atmos workflow validate-stack -f validate-enhanced -s "$(STACK)"

api-lint: ## Run linting (lint workflow)
	@atmos workflow lint -f lint

# =============================================================================
# Terminal Ergonomics & Power Features  
# =============================================================================

watch-validate: ## Continuously watch validation status
	@echo "$(CYAN)👀 Watching validation status (Ctrl+C to stop)...$(NC)"
	@watch -n 10 'make validate 2>/dev/null || echo "❌ Validation failed"'

watch-api-status: ## Watch the component list of the current stack
	@echo "$(CYAN)👀 Watching $(STACK) (Ctrl+C to stop)...$(NC)"
	@watch -n 10 'atmos list components -s "$(STACK)"'

validate-all: ## Validate all available stacks
	@echo "$(CYAN)🔍 Validating all stacks...$(NC)"
	@atmos workflow validate-all -f validate-enhanced

quick-health: ## Quick health check of infrastructure
	@echo "$(CYAN)🩺 Quick Health Check$(NC)"
	@echo "$(YELLOW)────────────────────────────────────────$(NC)"
	@echo "$(WHITE)Atmos Status:$(NC)"
	@atmos version 2>/dev/null && echo "$(GREEN)✅ Atmos OK$(NC)" || echo "$(RED)❌ Atmos issue$(NC)"
	@echo "$(WHITE)Terraform Status:$(NC)"
	@terraform version 2>/dev/null | head -1 && echo "$(GREEN)✅ Terraform OK$(NC)" || echo "$(YELLOW)ℹ️  Terraform not on PATH (Atmos installs the pinned version from dependencies.tools)$(NC)"
	@echo "$(WHITE)AWS Credentials:$(NC)"
	@aws sts get-caller-identity 2>/dev/null | jq -r '.Account' | xargs -I {} echo "$(GREEN)✅ AWS Account: {}$(NC)" || echo "$(RED)❌ AWS credentials issue$(NC)"
	@echo "$(WHITE)Project Structure:$(NC)"
	@test -f atmos.yaml && echo "$(GREEN)✅ atmos.yaml$(NC)" || echo "$(RED)❌ atmos.yaml missing$(NC)"
	@test -d components/terraform && echo "$(GREEN)✅ components/terraform/$(NC)" || echo "$(RED)❌ components missing$(NC)"
	@test -d stacks && echo "$(GREEN)✅ stacks/$(NC)" || echo "$(RED)❌ stacks missing$(NC)"

show-config: ## Show current configuration and derived values
	@echo "$(CYAN)⚙️  Current Configuration$(NC)"
	@echo "$(YELLOW)──────────────────────────────────────$(NC)"
	@echo "$(WHITE)Environment Variables:$(NC)"
	@echo "  TENANT:      $(GREEN)$(TENANT)$(NC)"
	@echo "  STAGE:       $(GREEN)$(STAGE)$(NC)"
	@echo "  ENVIRONMENT: $(GREEN)$(ENVIRONMENT)$(NC)"
	@echo "  REGION:      $(GREEN)$(REGION)$(NC)"
	@echo "$(WHITE)Derived Values:$(NC)"
	@echo "  STACK:           $(GREEN)$(STACK)$(NC)"
	@echo "$(WHITE)AWS Configuration:$(NC)"
	@aws configure list 2>/dev/null || echo "$(YELLOW)⚠️  AWS CLI not configured$(NC)"
	@echo "$(WHITE)Current Directory:$(NC)"
	@echo "  $(GREEN)$$(pwd)$(NC)"

list-stacks-friendly: ## List stacks with friendly names
	@echo "$(CYAN)📋 Available Infrastructure Stacks$(NC)"
	@echo "$(YELLOW)──────────────────────────────────────────────────────$(NC)"
	@./scripts/list_stacks.sh

component-info: ## Show information about a Terraform root module (usage: make component-info COMPONENT=vpc)
ifndef COMPONENT
	@echo "$(RED)❌ COMPONENT required. Usage: make component-info COMPONENT=vpc$(NC)"
else
	@echo "$(CYAN)📦 Component Information: $(COMPONENT)$(NC)"
	@echo "$(YELLOW)────────────────────────────────────$(NC)"
	@test -d components/terraform/$(COMPONENT) && echo "$(GREEN)✅ Component exists$(NC)" || echo "$(RED)❌ Component not found$(NC)"
	@test -f components/terraform/$(COMPONENT)/README.md && echo "$(WHITE)📖 README:$(NC)" && head -10 components/terraform/$(COMPONENT)/README.md || echo "$(YELLOW)⚠️  No README found$(NC)"
	@test -f components/terraform/$(COMPONENT)/variables.tf && echo "$(WHITE)📥 Variables:$(NC)" && grep -E '^variable' components/terraform/$(COMPONENT)/variables.tf | wc -l | xargs -I {} echo "  {} variables defined" || echo "$(YELLOW)⚠️  No variables.tf$(NC)"
	@test -f components/terraform/$(COMPONENT)/outputs.tf && echo "$(WHITE)📤 Outputs:$(NC)" && grep -E '^output' components/terraform/$(COMPONENT)/outputs.tf | wc -l | xargs -I {} echo "  {} outputs defined" || echo "$(YELLOW)⚠️  No outputs.tf$(NC)"
endif

# =============================================================================
# Enhanced Development Workflows
# =============================================================================

dev-cycle: ## Full development cycle: lint -> validate -> plan
	@echo "$(CYAN)🔄 Running full development cycle...$(NC)"
	@echo "$(YELLOW)Step 1/3: Linting$(NC)"
	@make lint
	@echo "$(YELLOW)Step 2/3: Validation$(NC)"
	@make validate
	@echo "$(YELLOW)Step 3/3: Planning$(NC)"
	@make plan
	@echo "$(GREEN)✅ Development cycle complete$(NC)"

dev-cycle-component: ## Component development cycle (usage: make dev-cycle-component COMPONENT=vpc/main)
ifndef COMPONENT
	@echo "$(RED)❌ COMPONENT required. Usage: make dev-cycle-component COMPONENT=vpc/main$(NC)"
else
	@echo "$(CYAN)🔄 Component development cycle: $(COMPONENT)$(NC)"
	@echo "$(YELLOW)Step 1/4: Component info$(NC)"
	@atmos describe component $(COMPONENT) -s $(STACK) --process-functions=false --query .component
	@echo "$(YELLOW)Step 2/4: Linting$(NC)"
	@make lint
	@echo "$(YELLOW)Step 3/4: Validation$(NC)"
	@atmos terraform validate $(COMPONENT) -s $(STACK)
	@echo "$(YELLOW)Step 4/4: Planning$(NC)"
	@atmos terraform plan $(COMPONENT) -s $(STACK)
	@echo "$(GREEN)✅ Component $(COMPONENT) development cycle complete$(NC)"
endif

safety-check: ## Comprehensive safety checks before any apply operation
	@echo "$(CYAN)🛡️  Running safety checks...$(NC)"
	@echo "$(YELLOW)──────────────────────────────────────$(NC)"
	@echo "$(WHITE)1. Configuration validation$(NC)"
	@make validate
	@echo "$(WHITE)2. AWS credentials check$(NC)"
	@aws sts get-caller-identity >/dev/null && echo "$(GREEN)✅ AWS credentials valid$(NC)" || (echo "$(RED)❌ AWS credentials invalid$(NC)" && exit 1)
	@echo "$(WHITE)3. Atmos version check$(NC)"
	@atmos version
	@echo "$(WHITE)4. State backend check$(NC)"
	@atmos workflow verify -f bootstrap -s "$(STACK)"
	@echo "$(GREEN)✅ All safety checks passed$(NC)"

# =============================================================================
# Terminal Integration Helpers
# =============================================================================

# Printed by `make shell-functions`; kept in a variable because a recipe cannot hold a heredoc
define SHELL_FUNCTIONS
# Atmos Infrastructure Functions (stacks: <tenant>-<stage>-<environment>)
infra-stacks() {
  atmos list stacks
}

infra-validate-stack() {
  local stack=$${1:-fnx-dev-testenv-01}
  atmos workflow validate-stack -f validate-enhanced -s $$stack
}

infra-lint() {
  atmos workflow lint -f lint
}

# Terraform shortcuts
tf-plan() {
  local component=$${1:?Component required, e.g. vpc/main}
  local stack=$${2:-fnx-dev-testenv-01}
  atmos terraform plan $$component -s $$stack
}

tf-validate() {
  local component=$${1:?Component required, e.g. vpc/main}
  local stack=$${2:-fnx-dev-testenv-01}
  atmos terraform validate $$component -s $$stack
}

# Infrastructure aliases
alias infra-status='make quick-health'
alias infra-validate='make validate'
alias infra-plan='make plan'
alias infra-workflows='atmos list workflows'
endef
export SHELL_FUNCTIONS

shell-functions: ## Generate shell functions for .bashrc/.zshrc  
	@echo "$(CYAN)🐚 Shell Functions for .bashrc or .zshrc$(NC)"
	@echo "$(YELLOW)────────────────────────────────────────────────────$(NC)"
	@printf '%s\n' "$$SHELL_FUNCTIONS"
	@echo "$(GREEN)💡 Copy the above functions to your shell profile!$(NC)"
	@echo
	@echo "$(WHITE)Examples:$(NC)"
	@echo "  make status                           # Show current stack status"
	@echo "  make validate                        # Validate all configurations"
	@echo "  make plan STAGE=prod ENVIRONMENT=production  # Plan another stack"
	@echo "  make apply STACK=fnx-staging-staging-01      # Apply to staging"
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
	@echo
	@echo "$(WHITE)Available Stacks:$(NC)"
	@echo "===================="
	@atmos list stacks
	@echo
	@echo "$(WHITE)Current Stack Components:$(NC)"
	@echo "=========================="
	@atmos list components -s "$(STACK)" 2>/dev/null || echo "No components found for $(STACK)"

# =============================================================================
# Core Infrastructure Commands
# =============================================================================

validate: ## Validate all Terraform configurations
	@echo "$(BLUE)Validating configurations for $(STACK)...$(NC)"
	@atmos workflow validate -f validate -s "$(STACK)"

lint: ## Lint and format all code
	@echo "$(BLUE)Linting and formatting code...$(NC)"
	@atmos workflow lint -f lint

plan: ## Plan infrastructure changes
	@echo "$(BLUE)Planning infrastructure changes for $(STACK)...$(NC)"
	@atmos workflow plan -f plan-environment -s "$(STACK)"

apply: ## Apply infrastructure changes (with confirmation)
	@echo "$(YELLOW)⚠️  This will apply changes to $(STACK)!$(NC)"
	@read -p "Are you sure? (y/N) " -n 1 -r; \
	echo; \
	if [ "$$REPLY" = "y" ] || [ "$$REPLY" = "Y" ]; then \
		echo "$(BLUE)Applying infrastructure changes...$(NC)"; \
		atmos workflow apply -f apply-environment -s "$(STACK)"; \
	else \
		echo "$(YELLOW)Apply cancelled.$(NC)"; \
	fi

destroy: ## Destroy infrastructure (the workflow asks for the stack name twice)
	@echo "$(RED)⚠️  DANGER: This destroys every component of the stack you type (e.g. $(STACK))!$(NC)"
	@atmos workflow destroy -f destroy-environment

status: ## Show current infrastructure status
	@echo "$(WHITE)Infrastructure Status for $(STACK)$(NC)"
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
	@atmos workflow drift-detection -f drift-detection -s "$(STACK)"

# =============================================================================
# Component-Specific Commands
# =============================================================================

plan-vpc: ## Plan VPC changes
	@echo "$(BLUE)Planning VPC changes...$(NC)"
	@atmos terraform plan vpc/main -s "$(STACK)"

apply-vpc: ## Apply VPC changes
	@echo "$(BLUE)Applying VPC changes...$(NC)"
	@atmos terraform apply vpc/main -s "$(STACK)"

plan-eks: ## Plan EKS changes
	@echo "$(BLUE)Planning EKS changes...$(NC)"
	@atmos terraform plan eks/main -s "$(STACK)"

apply-eks: ## Apply EKS changes
	@echo "$(BLUE)Applying EKS changes...$(NC)"
	@atmos terraform apply eks/main -s "$(STACK)"

plan-component: ## Plan specific component (usage: make plan-component COMPONENT=vpc/main)
	@if [ -z "$(COMPONENT)" ]; then \
		echo "$(RED)Error: COMPONENT variable is required$(NC)"; \
		echo "Usage: make plan-component COMPONENT=vpc/main"; \
		exit 1; \
	fi
	@echo "$(BLUE)Planning $(COMPONENT) changes...$(NC)"
	@atmos terraform plan $(COMPONENT) -s "$(STACK)"

apply-component: ## Apply specific component (usage: make apply-component COMPONENT=vpc/main)
	@if [ -z "$(COMPONENT)" ]; then \
		echo "$(RED)Error: COMPONENT variable is required$(NC)"; \
		echo "Usage: make apply-component COMPONENT=vpc/main"; \
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
	@$(MAKE) install-toolchain

install-toolchain: ## Install the Terraform toolchain Atmos uses (version pinned in .atmos.env)
	@echo "$(BLUE)Installing Terraform $$(sed -n 's/^TERRAFORM_VERSION=//p' .atmos.env) via the Atmos toolchain.$(NC)"
	@atmos toolchain install hashicorp/terraform@$$(sed -n 's/^TERRAFORM_VERSION=//p' .atmos.env)

dev-start: ## Start development environment with Docker Compose
	@echo "$(BLUE)Starting development environment...$(NC)"
	@docker compose up -d

dev-stop: ## Stop development environment
	@echo "$(BLUE)Stopping development environment...$(NC)"
	@docker compose down

dev-logs: ## View development environment logs
	@echo "$(BLUE)Following development logs...$(NC)"
	@docker compose logs -f

dev-reset: ## Reset development environment (removes all data)
	@echo "$(RED)⚠️  This will remove all development data!$(NC)"
	@docker compose down -v

# =============================================================================
# Environment Management
# =============================================================================

onboard: ## Quick environment onboarding with defaults (scaffold stack + bootstrap backend)
	@echo "$(BLUE)Onboarding environment $(STACK)...$(NC)"
	@echo "Using default VPC CIDR: 10.0.0.0/16"
	@./scripts/new-environment.sh --tenant $(TENANT) --stage $(STAGE) --environment $(ENVIRONMENT) --region $(REGION) --vpc-cidr 10.0.0.0/16 --no-workspace

onboard-custom: ## Custom environment onboarding (usage: make onboard-custom VPC_CIDR=10.1.0.0/16)
	@if [ -z "$(VPC_CIDR)" ]; then \
		echo "$(RED)Error: VPC_CIDR variable is required$(NC)"; \
		echo "Usage: make onboard-custom VPC_CIDR=10.1.0.0/16"; \
		exit 1; \
	fi
	@echo "$(BLUE)Onboarding environment $(STACK) with VPC CIDR $(VPC_CIDR)...$(NC)"
	@./scripts/new-environment.sh --tenant $(TENANT) --stage $(STAGE) --environment $(ENVIRONMENT) --region $(REGION) --vpc-cidr $(VPC_CIDR) --no-workspace

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

check-security: ## Run security checks (Trivy + Checkov via the security-scan workflow)
	@echo "$(BLUE)Running security checks...$(NC)"
	@atmos workflow security-scan -f lint
	@echo "$(GREEN)✅ Security check complete$(NC)"

check-costs: ## Estimate infrastructure costs
	@echo "$(BLUE)Checking estimated costs...$(NC)"
	@if command -v infracost >/dev/null 2>&1; then \
		echo "💰 Running infracost analysis..."; \
		for dir in $$(find ./components/terraform -mindepth 1 -maxdepth 1 -type d); do \
			if [ -f "$$dir/main.tf" ]; then \
				echo "Analyzing $$dir..."; \
				infracost breakdown --path=$$dir --format=table || true; \
			fi; \
		done; \
	elif command -v terraformer >/dev/null 2>&1; then \
		echo "📊 Using terraformer for cost estimation..."; \
		echo "$(YELLOW)Note: Manual cost analysis required$(NC)"; \
	else \
		echo "$(YELLOW)⚠️  No cost analysis tool found. Install infracost:$(NC)"; \
		echo "  brew install infracost/brew/infracost"; \
		echo "  curl -fsSL https://raw.githubusercontent.com/infracost/infracost/master/scripts/install.sh | sh"; \
		echo "  infracost auth login"; \
		exit 1; \
	fi
	@echo "$(GREEN)✅ Cost analysis complete$(NC)"

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

update-docs: ## Regenerate component README docs (terraform-docs pre-commit hook)
	@echo "$(BLUE)Updating documentation...$(NC)"
	@pre-commit run terraform_docs --all-files

backup-state: ## Backup Terraform outputs and state listings (STACK=<stack>, or ALL_STACKS=1)
	@echo "$(BLUE)Creating state backup...$(NC)"
	@BACKUP_DIR="./backups/state/$$(date +%Y%m%d_%H%M%S)"; \
	mkdir -p $$BACKUP_DIR; \
	echo "📦 Backing up state files to $$BACKUP_DIR..."; \
	for stack in $(if $(ALL_STACKS),$$(atmos list stacks),$(STACK)); do \
		echo "  Backing up stack: $$stack"; \
		for component in $$(atmos list components -s $$stack | cut -f1); do \
			name=$$stack-$$(echo $$component | tr / -); \
			atmos terraform output $$component -s $$stack -json > $$BACKUP_DIR/outputs_$$name.json 2>/dev/null || echo "    No outputs for $$component"; \
			atmos terraform state list $$component -s $$stack > $$BACKUP_DIR/state_list_$$name.txt 2>/dev/null || echo "    No state for $$component"; \
		done; \
	done; \
	echo "$(GREEN)✅ State backup created in $$BACKUP_DIR$(NC)"

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
	@atmos describe stacks -s "$(STACK)" --process-functions=false >/dev/null 2>&1 && echo "✅ Current stack configuration is valid" || echo "❌ Current stack configuration has issues"

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
	@$(MAKE) STACK=fnx-dev-testenv-01 status

staging: ## Switch to staging environment  
	@$(MAKE) STACK=fnx-staging-staging-01 status

prod: ## Switch to production environment
	@$(MAKE) STACK=fnx-prod-production status

# =============================================================================
# AWS Backend Setup and Management
# =============================================================================
# State lives in the S3 bucket <tenant>-terraform-state (native lockfile
# locking, no DynamoDB), created and managed by the backend/main component.

setup-aws-backend: ## Create the state bucket and apply backend/main (usage: make setup-aws-backend STACK=fnx-dev-testenv-01)
	@echo "$(BLUE)Setting up AWS backend infrastructure for $(STACK)...$(NC)"
	@atmos workflow backend-only -f bootstrap -s "$(STACK)"

setup-aws-backend-dry-run: ## Show the backend configuration and plan without applying
	@atmos terraform backend describe backend/main -s "$(STACK)"
	@atmos terraform plan backend/main -s "$(STACK)"

validate-aws-setup: ## Validate existing AWS backend setup
	@echo "$(BLUE)Validating AWS backend setup for $(STACK)...$(NC)"
	@atmos workflow verify -f bootstrap -s "$(STACK)"

bootstrap-environment: ## Complete environment bootstrap (backend + validation)
	@echo "$(BLUE)Bootstrapping complete environment: $(STACK)$(NC)"
	@echo "Step 1/3: Setting up AWS backend infrastructure..."
	@$(MAKE) --no-print-directory setup-aws-backend STACK=$(STACK)
	@echo
	@echo "Step 2/3: Validating backend setup..."
	@$(MAKE) --no-print-directory validate-aws-setup STACK=$(STACK)
	@echo
	@echo "Step 3/3: Running configuration validation..."
	@$(MAKE) --no-print-directory validate STACK=$(STACK)
	@echo
	@echo "$(GREEN)✅ Environment bootstrap completed successfully!$(NC)"
	@echo "Next steps:"
	@echo "  1. Plan infrastructure: make plan STACK=$(STACK)"
	@echo "  2. Deploy layer by layer: atmos workflow deploy -f deploy-full-stack -s $(STACK)"

cleanup-aws-backend: ## Destroy the backend/main component (DANGEROUS; the workflow asks for confirmation)
	@echo "$(RED)⚠️  WARNING: This destroys the Terraform state backend component!$(NC)"
	@atmos workflow destroy -f destroy-backend

# AWS Backend Quick Commands for Common Environments
setup-aws-dev: ## Quick setup for development backend
	@$(MAKE) setup-aws-backend STACK=fnx-dev-testenv-01

setup-aws-staging: ## Quick setup for staging backend  
	@$(MAKE) setup-aws-backend STACK=fnx-staging-staging-01

setup-aws-prod: ## Quick setup for production backend
	@$(MAKE) setup-aws-backend STACK=fnx-prod-production

# =============================================================================
# Advanced Operations
# =============================================================================

import-resource: ## Import existing resource into Terraform state
	@echo "$(BLUE)Starting resource import workflow...$(NC)"
	@atmos workflow import -f import -s "$(STACK)"

rotate-certs: ## Rotate SSL certificates
	@echo "$(BLUE)Rotating SSL certificates...$(NC)"
	@atmos workflow rotate -f rotate-certificate

state-ops: ## Perform state operations
	@echo "$(BLUE)Starting state operations workflow...$(NC)"
	@STACK="$(STACK)" atmos workflow list-locks -f state-operations

# =============================================================================
# Debugging and Troubleshooting
# =============================================================================

debug-stack: ## Debug current stack configuration
	@echo "$(WHITE)Stack Debug Information$(NC)"
	@echo "========================"
	@echo "Stack Name: $(STACK)"
	@echo
	@echo "$(WHITE)Stack Description:$(NC)"
	@atmos describe stacks -s "$(STACK)" --process-functions=false || echo "Failed to describe stack"
	@echo
	@echo "$(WHITE)Stack Components:$(NC)"
	@atmos list components -s "$(STACK)" || echo "Failed to list components"

debug-env: ## Debug environment variables and configuration
	@echo "$(WHITE)Environment Debug Information$(NC)"
	@echo "============================="
	@echo "TENANT: $(TENANT)"
	@echo "STAGE: $(STAGE)"
	@echo "ENVIRONMENT: $(ENVIRONMENT)"
	@echo "REGION: $(REGION)"
	@echo "STACK: $(STACK)"
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
	@RESULTS_DIR="./benchmarks/$$(date +%Y%m%d_%H%M%S)"; \
	mkdir -p $$RESULTS_DIR; \
	echo "🚀 Benchmarking Terraform operations..."; \
	echo "Results will be saved to $$RESULTS_DIR"; \
	echo "Component,Operation,Duration,Status" > $$RESULTS_DIR/benchmark_results.csv; \
	for component in $$(atmos list components -s "$(STACK)" | cut -f1); do \
		echo "  📊 Benchmarking $$component..."; \
		START_TIME=$$(date +%s); \
		if timeout 300 atmos terraform validate $$component -s "$(STACK)" > /dev/null 2>&1; then \
			END_TIME=$$(date +%s); \
			DURATION=$$((END_TIME - START_TIME)); \
			echo "$$component,validate,$$DURATION,success" >> $$RESULTS_DIR/benchmark_results.csv; \
			echo "    ✅ Validation: $${DURATION}s"; \
		else \
			echo "$$component,validate,-1,failed" >> $$RESULTS_DIR/benchmark_results.csv; \
			echo "    ❌ Validation failed"; \
		fi; \
	done; \
	echo "$(GREEN)✅ Benchmarks complete - results in $$RESULTS_DIR$(NC)"

profile: ## Profile resource usage and costs
	@echo "$(BLUE)Profiling resource usage...$(NC)"
	@PROFILE_DIR="./profiles/$$(date +%Y%m%d_%H%M%S)"; \
	mkdir -p $$PROFILE_DIR; \
	echo "📈 Analyzing resource usage..."; \
	echo "Component,ResourceType,Count,EstimatedMonthlyCost" > $$PROFILE_DIR/resource_profile.csv; \
	for component in $$(find ./components/terraform -mindepth 1 -maxdepth 1 -type d -exec basename {} \;); do \
		if [ -f "./components/terraform/$$component/main.tf" ]; then \
			echo "  🔍 Profiling $$component..."; \
			RESOURCE_COUNT=$$(grep -c "^resource" ./components/terraform/$$component/main.tf 2>/dev/null || echo "0"); \
			echo "    Resources: $$RESOURCE_COUNT"; \
			echo "$$component,total,$$RESOURCE_COUNT,N/A" >> $$PROFILE_DIR/resource_profile.csv; \
		fi; \
	done; \
	echo "🎯 Generating usage summary..."; \
	wc -l ./components/terraform/*/*.tf 2>/dev/null | tail -n +2 | head -n -1 > $$PROFILE_DIR/code_metrics.txt; \
	find ./components/terraform -name "*.tf" -exec grep -l "aws_instance\|aws_rds\|aws_eks" {} \; | wc -l > $$PROFILE_DIR/high_cost_components.txt; \
	echo "$(GREEN)✅ Resource profiling complete - results in $$PROFILE_DIR$(NC)"

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