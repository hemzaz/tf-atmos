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
	@echo "$(WHITE)Power User Features:$(NC)"
	@echo "  $(YELLOW)API Mode:$(NC)       make api-serve     $(GREEN)# Start REST API server$(NC)"
	@echo "  $(YELLOW)Watch Mode:$(NC)     make watch-validate $(GREEN)# Continuous validation$(NC)"
	@echo "  $(YELLOW)Batch Ops:$(NC)      make validate-all  $(GREEN)# Validate all stacks$(NC)"
	@echo
	@echo "$(WHITE)Quick Examples:$(NC)"
	@echo "  $(GREEN)make validate TENANT=fnx ENVIRONMENT=prod$(NC)"
	@echo "  $(GREEN)make plan COMPONENT=vpc$(NC)"
	@echo "  $(GREEN)make api-validate-stack STACK=fnx-dev-testenv-01$(NC)"

# =============================================================================
# Unified Gaia Interface - Single Entry Point  
# =============================================================================

gaia-smart: ## 🧠 Intelligent command interface (usage: make gaia-smart QUERY="validate my infrastructure")
	@if [ -z "$(QUERY)" ]; then \
		echo "$(RED)Error: QUERY variable is required$(NC)"; \
		echo "Usage: make gaia-smart QUERY=\"your natural language request\""; \
		echo "Examples:"; \
		echo "  make gaia-smart QUERY=\"validate my infrastructure\""; \
		echo "  make gaia-smart QUERY=\"deploy to staging environment\""; \
		echo "  make gaia-smart QUERY=\"check security issues\""; \
		exit 1; \
	fi
	@echo "$(CYAN)🧠 Processing: $(QUERY)$(NC)"
	@gaia smart "$(QUERY)" $(if $(EXECUTE),--execute,)

gaia-orchestrate: ## 🎼 Orchestrate tasks with dependency resolution
	@echo "$(CYAN)🎼 Task Orchestration$(NC)"
	@gaia orchestrate $(if $(ENVIRONMENT),--environment $(ENVIRONMENT),) $(if $(TASKS),$(foreach task,$(TASKS),--task $(task)),) $(if $(PLAN_ONLY),--plan-only,)

gaia-hygiene: ## 🧹 Comprehensive system hygiene and maintenance
	@echo "$(CYAN)🧹 System Hygiene$(NC)"
	@gaia hygiene $(if $(SCOPE),--scope $(SCOPE),) $(if $(FIX),--fix,) $(if $(REPORT),--report,)

gaia-context: ## 🎯 Manage development context (usage: make gaia-context TENANT=fnx ACCOUNT=dev ENVIRONMENT=testenv-01)
	@gaia context $(if $(TENANT),--tenant $(TENANT),) $(if $(ACCOUNT),--account $(ACCOUNT),) $(if $(ENVIRONMENT),--environment $(ENVIRONMENT),) $(if $(SHOW),--show,)

gaia-dashboard: ## 📊 Unified system dashboard
	@gaia dashboard

# Quick shortcuts for power users
gaia: gaia-dashboard ## Quick alias for unified dashboard
smart: gaia-smart ## Quick alias for smart interface  
orchestrate: gaia-orchestrate ## Quick alias for orchestration
hygiene: gaia-hygiene ## Quick alias for system hygiene

# =============================================================================
# Power User & API Features
# =============================================================================

api-serve: ## Start Gaia API server for terminal-first workflows
	@echo "$(CYAN)🚀 Starting Gaia API server...$(NC)"
	@gaia serve --port 8080

api-docs: ## Show API documentation and examples
	@./scripts/curl-examples.sh

api-health: ## Check API server health
	@echo "$(CYAN)🩺 Checking API health...$(NC)"
	@curl -s http://localhost:8080/health | jq '.' || echo "$(RED)❌ API server not running. Start with: make api-serve$(NC)"

api-status: ## Get infrastructure status via API
	@echo "$(CYAN)📊 Infrastructure Status:$(NC)"
	@curl -s http://localhost:8080/status | jq '.summary' || echo "$(RED)❌ API server not running$(NC)"

api-list-stacks: ## List all stacks via API
	@echo "$(CYAN)📋 Available Stacks:$(NC)"
	@curl -s http://localhost:8080/stacks | jq -r '.stacks[]' || echo "$(RED)❌ API server not running$(NC)"

api-validate-stack: ## Validate specific stack via API (usage: make api-validate-stack STACK=fnx-dev-testenv-01)
	@echo "$(CYAN)✅ Validating stack: $(STACK)$(NC)"
	@curl -X POST http://localhost:8080/stacks/$(STACK)/validate | jq '.summary' || echo "$(RED)❌ API server not running$(NC)"

api-lint: ## Run linting via API
	@echo "$(CYAN)🧹 Linting configurations...$(NC)"
	@curl -X POST http://localhost:8080/lint | jq -r '.stdout' || echo "$(RED)❌ API server not running$(NC)"

# =============================================================================
# Terminal Ergonomics & Power Features  
# =============================================================================

watch-validate: ## Continuously watch validation status
	@echo "$(CYAN)👀 Watching validation status (Ctrl+C to stop)...$(NC)"
	@watch -n 10 'make validate 2>/dev/null || echo "❌ Validation failed"'

watch-api-status: ## Watch infrastructure status via API
	@echo "$(CYAN)👀 Watching API status (Ctrl+C to stop)...$(NC)"
	@watch -n 10 'curl -s http://localhost:8080/status | jq ".summary" 2>/dev/null || echo "❌ API unavailable"'

validate-all: ## Validate all available stacks
	@echo "$(CYAN)🔍 Validating all stacks...$(NC)"
	@for stack in $$(./scripts/list_stacks.sh | tail -n +2); do \
		echo "$(YELLOW)Validating: $$stack$(NC)"; \
		atmos workflow validate --file validate.yaml tenant=$$(echo $$stack | cut -d- -f1) account=$$(echo $$stack | cut -d- -f3) environment=$$(echo $$stack | cut -d- -f2) || true; \
	done

quick-health: ## Quick health check of infrastructure
	@echo "$(CYAN)🩺 Quick Health Check$(NC)"
	@echo "$(YELLOW)────────────────────────────────────────$(NC)"
	@echo "$(WHITE)Atmos Status:$(NC)"
	@atmos version 2>/dev/null && echo "$(GREEN)✅ Atmos OK$(NC)" || echo "$(RED)❌ Atmos issue$(NC)"
	@echo "$(WHITE)Terraform Status:$(NC)"
	@terraform version 2>/dev/null | head -1 && echo "$(GREEN)✅ Terraform OK$(NC)" || echo "$(RED)❌ Terraform issue$(NC)"
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
	@echo "  ACCOUNT:     $(GREEN)$(ACCOUNT)$(NC)"  
	@echo "  ENVIRONMENT: $(GREEN)$(ENVIRONMENT)$(NC)"
	@echo "  REGION:      $(GREEN)$(REGION)$(NC)"
	@echo "$(WHITE)Derived Values:$(NC)"
	@echo "  STACK:           $(GREEN)$(STACK)$(NC)"
	@echo "  FRIENDLY_STACK:  $(GREEN)$(FRIENDLY_STACK)$(NC)"
	@echo "$(WHITE)AWS Configuration:$(NC)"
	@aws configure list 2>/dev/null || echo "$(YELLOW)⚠️  AWS CLI not configured$(NC)"
	@echo "$(WHITE)Current Directory:$(NC)"
	@echo "  $(GREEN)$$(pwd)$(NC)"

list-stacks-friendly: ## List stacks with friendly names
	@echo "$(CYAN)📋 Available Infrastructure Stacks$(NC)"
	@echo "$(YELLOW)──────────────────────────────────────────────────────$(NC)"
	@./scripts/list_stacks.sh

component-info: ## Show information about a component (usage: make component-info COMPONENT=vpc)
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

dev-cycle-component: ## Component development cycle (usage: make dev-cycle-component COMPONENT=vpc)
ifndef COMPONENT
	@echo "$(RED)❌ COMPONENT required. Usage: make dev-cycle-component COMPONENT=vpc$(NC)"
else
	@echo "$(CYAN)🔄 Component development cycle: $(COMPONENT)$(NC)"
	@echo "$(YELLOW)Step 1/4: Component info$(NC)"
	@make component-info COMPONENT=$(COMPONENT)
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
	@echo "$(WHITE)3. Terraform version check$(NC)"
	@terraform version | head -1
	@echo "$(WHITE)4. Atmos version check$(NC)"
	@atmos version
	@echo "$(WHITE)5. State backend check$(NC)"
	@echo "$(GREEN)✅ All safety checks passed$(NC)"

# =============================================================================
# Terminal Integration Helpers
# =============================================================================

shell-functions: ## Generate shell functions for .bashrc/.zshrc  
	@echo "$(CYAN)🐚 Shell Functions for .bashrc or .zshrc$(NC)"
	@echo "$(YELLOW)────────────────────────────────────────────────────$(NC)"
	@cat << 'EOF'
# Gaia Infrastructure Management Functions
gaia-status() { 
  curl -s http://localhost:8080/status | jq '.summary' 2>/dev/null || echo "❌ Gaia API not running"
}

gaia-validate() {
  local stack=$${1:-fnx-dev-testenv-01}
  curl -X POST http://localhost:8080/stacks/$$stack/validate | jq '.summary' 2>/dev/null
}

gaia-quick() {
  echo "🚀 Quick Gaia Commands:"
  echo "  gaia-status          # Infrastructure status"
  echo "  gaia-validate [stack]  # Validate stack"
  echo "  gaia-lint            # Lint all configs"
  echo "  gaia-serve           # Start API server"
}

gaia-lint() {
  curl -X POST http://localhost:8080/lint | jq -r '.stdout' 2>/dev/null
}

gaia-serve() {
  echo "🚀 Starting Gaia API server..."
  gaia serve --port 8080
}

# Terraform shortcuts
tf-plan() {
  local component=$${1:?Component required}
  local stack=$${2:-fnx-dev-testenv-01}
  atmos terraform plan $$component -s $$stack
}

tf-validate() {
  local component=$${1:?Component required}
  local stack=$${2:-fnx-dev-testenv-01}
  atmos terraform validate $$component -s $$stack
}

# Infrastructure aliases
alias infra-status='make quick-health'
alias infra-validate='make validate'
alias infra-plan='make plan'
alias infra-api='gaia serve'
EOF
	@echo "$(GREEN)💡 Copy the above functions to your shell profile!$(NC)"
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
	if [ "$$REPLY" = "y" ] || [ "$$REPLY" = "Y" ]; then \
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
		if [ "$$REPLY" = "y" ] || [ "$$REPLY" = "Y" ]; then \
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
	@if command -v tfsec >/dev/null 2>&1; then \
		echo "🔍 Running tfsec security scan..."; \
		tfsec ./components/terraform/ --format compact || echo "$(YELLOW)⚠️  Security issues found - review above$(NC)"; \
	elif command -v checkov >/dev/null 2>&1; then \
		echo "🔍 Running checkov security scan..."; \
		checkov -d ./components/terraform/ --compact || echo "$(YELLOW)⚠️  Security issues found - review above$(NC)"; \
	else \
		echo "$(YELLOW)⚠️  No security scanner found. Install tfsec or checkov:$(NC)"; \
		echo "  brew install tfsec"; \
		echo "  pip install checkov"; \
		exit 1; \
	fi
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

update-docs: ## Update and migrate documentation
	@echo "$(BLUE)Updating documentation...$(NC)"
	@./scripts/migrate_docs.sh

backup-state: ## Backup Terraform state (for disaster recovery)
	@echo "$(BLUE)Creating state backup...$(NC)"
	@BACKUP_DIR="./backups/state/$$(date +%Y%m%d_%H%M%S)"; \
	mkdir -p $$BACKUP_DIR; \
	echo "📦 Backing up state files to $$BACKUP_DIR..."; \
	if [ -n "$(TENANT)" ] && [ -n "$(ACCOUNT)" ] && [ -n "$(ENVIRONMENT)" ]; then \
		echo "Backing up specific stack: $(TENANT)-$(ACCOUNT)-$(ENVIRONMENT)"; \
		atmos terraform output -s $(TENANT)-$(ACCOUNT)-$(ENVIRONMENT) > $$BACKUP_DIR/outputs_$(TENANT)-$(ACCOUNT)-$(ENVIRONMENT).json 2>/dev/null || echo "No outputs found"; \
		atmos terraform state list -s $(TENANT)-$(ACCOUNT)-$(ENVIRONMENT) > $$BACKUP_DIR/state_list_$(TENANT)-$(ACCOUNT)-$(ENVIRONMENT).txt 2>/dev/null || echo "No state found"; \
	else \
		echo "Backing up all available stacks..."; \
		for stack in $$(./scripts/list_stacks.sh | grep -v "Available stacks:" | sed 's/^[[:space:]]*//'); do \
			if [ -n "$$stack" ]; then \
				echo "  Backing up stack: $$stack"; \
				atmos terraform output -s $$stack > $$BACKUP_DIR/outputs_$$stack.json 2>/dev/null || echo "    No outputs for $$stack"; \
				atmos terraform state list -s $$stack > $$BACKUP_DIR/state_list_$$stack.txt 2>/dev/null || echo "    No state for $$stack"; \
			fi; \
		done; \
	fi; \
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
# AWS Backend Setup and Management
# =============================================================================

setup-aws-backend: ## Setup AWS backend infrastructure (usage: make setup-aws-backend TENANT=fnx ACCOUNT=dev ENVIRONMENT=testenv-01)
	@if [ -z "$(TENANT)" ] || [ -z "$(ACCOUNT)" ] || [ -z "$(ENVIRONMENT)" ]; then \
		echo "$(RED)Error: TENANT, ACCOUNT, and ENVIRONMENT variables are required$(NC)"; \
		echo "Usage: make setup-aws-backend TENANT=fnx ACCOUNT=dev ENVIRONMENT=testenv-01"; \
		echo "Optional: REGION=us-west-2 ASSUME_ROLE=arn:aws:iam::123456789:role/Role"; \
		exit 1; \
	fi
	@echo "$(BLUE)Setting up AWS backend infrastructure...$(NC)"
	@./scripts/aws-setup.sh \
		--tenant $(TENANT) \
		--account $(ACCOUNT) \
		--environment $(ENVIRONMENT) \
		$(if $(REGION),--region $(REGION),) \
		$(if $(ASSUME_ROLE),--assume-role $(ASSUME_ROLE),) \
		$(if $(KMS_KEY),--kms-key-id $(KMS_KEY),) \
		$(if $(DRY_RUN),--dry-run,) \
		$(if $(FORCE),--force,)

setup-aws-backend-dry-run: ## Dry run AWS backend setup (shows what would be created)
	@$(MAKE) setup-aws-backend DRY_RUN=true TENANT=$(TENANT) ACCOUNT=$(ACCOUNT) ENVIRONMENT=$(ENVIRONMENT)

validate-aws-setup: ## Validate existing AWS backend setup
	@if [ -z "$(TENANT)" ] || [ -z "$(ACCOUNT)" ] || [ -z "$(ENVIRONMENT)" ]; then \
		echo "$(RED)Error: TENANT, ACCOUNT, and ENVIRONMENT variables are required$(NC)"; \
		echo "Usage: make validate-aws-setup TENANT=fnx ACCOUNT=dev ENVIRONMENT=testenv-01"; \
		exit 1; \
	fi
	@echo "$(BLUE)Validating AWS backend setup...$(NC)"
	@atmos workflow bootstrap-backend verify \
		tenant=$(TENANT) \
		account=$(ACCOUNT) \
		environment=$(ENVIRONMENT) \
		$(if $(REGION),region=$(REGION),)

bootstrap-environment: ## Complete environment bootstrap (backend + validation)
	@if [ -z "$(TENANT)" ] || [ -z "$(ACCOUNT)" ] || [ -z "$(ENVIRONMENT)" ]; then \
		echo "$(RED)Error: TENANT, ACCOUNT, and ENVIRONMENT variables are required$(NC)"; \
		echo "Usage: make bootstrap-environment TENANT=fnx ACCOUNT=dev ENVIRONMENT=testenv-01"; \
		exit 1; \
	fi
	@echo "$(BLUE)Bootstrapping complete environment: $(TENANT)-$(ACCOUNT)-$(ENVIRONMENT)$(NC)"
	@echo "Step 1/3: Setting up AWS backend infrastructure..."
	@$(MAKE) setup-aws-backend TENANT=$(TENANT) ACCOUNT=$(ACCOUNT) ENVIRONMENT=$(ENVIRONMENT) $(if $(REGION),REGION=$(REGION),)
	@echo
	@echo "Step 2/3: Validating backend setup..."
	@$(MAKE) validate-aws-setup TENANT=$(TENANT) ACCOUNT=$(ACCOUNT) ENVIRONMENT=$(ENVIRONMENT) $(if $(REGION),REGION=$(REGION),)
	@echo
	@echo "Step 3/3: Running configuration validation..."
	@$(MAKE) validate TENANT=$(TENANT) ACCOUNT=$(ACCOUNT) ENVIRONMENT=$(ENVIRONMENT)
	@echo
	@echo "$(GREEN)✅ Environment bootstrap completed successfully!$(NC)"
	@echo "Next steps:"
	@echo "  1. Apply backend component: make apply-component COMPONENT=backend"
	@echo "  2. Initialize other components: make validate"
	@echo "  3. Plan infrastructure: make plan"

cleanup-aws-backend: ## Clean up AWS backend infrastructure (DANGEROUS!)
	@if [ -z "$(TENANT)" ] || [ -z "$(ACCOUNT)" ] || [ -z "$(ENVIRONMENT)" ]; then \
		echo "$(RED)Error: TENANT, ACCOUNT, and ENVIRONMENT variables are required$(NC)"; \
		echo "Usage: make cleanup-aws-backend TENANT=fnx ACCOUNT=dev ENVIRONMENT=testenv-01"; \
		exit 1; \
	fi
	@echo "$(RED)⚠️  WARNING: This will DELETE your AWS backend infrastructure!$(NC)"
	@echo "Resources to be deleted:"
	@echo "  S3 Bucket: $(TENANT)-$(ACCOUNT)-$(ENVIRONMENT)-terraform-state"
	@echo "  DynamoDB Table: $(TENANT)-$(ACCOUNT)-$(ENVIRONMENT)-terraform-locks"
	@echo "  Region: $(or $(REGION),us-east-1)"
	@echo
	@echo "$(WHITE)Type '$(TENANT)-$(ACCOUNT)-$(ENVIRONMENT)' to confirm deletion:$(NC)"
	@read -r confirmation && \
	if [ "$$confirmation" = "$(TENANT)-$(ACCOUNT)-$(ENVIRONMENT)" ]; then \
		echo "$(YELLOW)Proceeding with backend cleanup...$(NC)"; \
		atmos workflow bootstrap-backend cleanup \
			tenant=$(TENANT) \
			account=$(ACCOUNT) \
			environment=$(ENVIRONMENT) \
			$(if $(REGION),region=$(REGION),) \
			$(if $(FORCE),force=true,); \
	else \
		echo "$(GREEN)Cleanup cancelled - confirmation didn't match$(NC)"; \
	fi

# AWS Backend Quick Commands for Common Environments
setup-aws-dev: ## Quick setup for development backend
	@$(MAKE) setup-aws-backend TENANT=fnx ACCOUNT=dev ENVIRONMENT=testenv-01

setup-aws-staging: ## Quick setup for staging backend  
	@$(MAKE) setup-aws-backend TENANT=fnx ACCOUNT=staging ENVIRONMENT=staging-01

setup-aws-prod: ## Quick setup for production backend
	@$(MAKE) setup-aws-backend TENANT=fnx ACCOUNT=prod ENVIRONMENT=production REGION=us-west-2

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
	@RESULTS_DIR="./benchmarks/$$(date +%Y%m%d_%H%M%S)"; \
	mkdir -p $$RESULTS_DIR; \
	echo "🚀 Benchmarking Terraform operations..."; \
	echo "Results will be saved to $$RESULTS_DIR"; \
	echo "Component,Operation,Duration,Status" > $$RESULTS_DIR/benchmark_results.csv; \
	for component in $$(find ./components/terraform -mindepth 1 -maxdepth 1 -type d -exec basename {} \;); do \
		if [ -f "./components/terraform/$$component/main.tf" ]; then \
			echo "  📊 Benchmarking $$component..."; \
			START_TIME=$$(date +%s); \
			if timeout 300 atmos terraform validate $$component -s fnx-dev-testenv-01 > /dev/null 2>&1; then \
				END_TIME=$$(date +%s); \
				DURATION=$$((END_TIME - START_TIME)); \
				echo "$$component,validate,$$DURATION,success" >> $$RESULTS_DIR/benchmark_results.csv; \
				echo "    ✅ Validation: $${DURATION}s"; \
			else \
				echo "$$component,validate,-1,failed" >> $$RESULTS_DIR/benchmark_results.csv; \
				echo "    ❌ Validation failed"; \
			fi; \
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