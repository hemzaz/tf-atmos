# =============================================================================
# Terraform/Atmos Infrastructure Makefile
# =============================================================================
# Thin shortcuts around Atmos commands and workflows. Run 'make help' to list them.

.PHONY: help lint validate validate-all sweep plan apply destroy status drift \
	plan-component apply-component onboard onboard-custom list-stacks check-security \
	setup-aws-backend-cold-start setup-aws-backend setup-aws-backend-dry-run \
	validate-aws-setup bootstrap-environment cleanup-aws-backend import-resource \
	rotate-certs state-ops clean update-docs
.DEFAULT_GOAL := help

# =============================================================================
# Configuration
# =============================================================================

# Default values - can be overridden via environment or command line.
# Stack names follow atmos.yaml name_template: <tenant>-<environment>-<stage>[-<name>],
# environment being REGION's code (fnx-ue1-dev, fnx-ue1-staging, fnx-ue1-prod) and
# NAME an optional lane. ACCOUNT is accepted as an alias for STAGE.
TENANT ?= fnx
STAGE ?= $(or $(ACCOUNT),dev)
REGION ?= us-east-1
NAME ?=

# sq single-quotes a make value for the shell, so a value is never shell syntax.
# Every user value (TENANT, STAGE, REGION, ENVIRONMENT, NAME, STACK, COMPONENT,
# ANSWERS, VPC_CIDR, VPC_CIDR_SERVICES, BACKEND_STACK) reaches a recipe's shell
# only through sq, echoes and -s arguments included: inside double quotes a
# $(...) would still run. scripts/test-scaffold-stack.sh runs recipes with
# hostile values.
sq = '$(subst ','\'',$(1))'

# Derived values (STACK can also be passed directly: make plan STACK=fnx-ue1-prod)
ENVIRONMENT ?= $(shell ./scripts/stack-name.sh region-code $(call sq,$(REGION)))
ifeq ($(origin STACK)$(strip $(ENVIRONMENT)),undefined)
ifeq ($(origin ENVIRONMENT),file)
$(error No region code for REGION=$(REGION): add stacks/mixins/region/$(REGION).yaml, or pass STACK=<stack>)
else
$(error ENVIRONMENT is empty: unset it to derive the region code from REGION, or pass STACK=<stack>)
endif
endif
STACK ?= $(TENANT)-$(ENVIRONMENT)-$(STAGE)$(if $(NAME),-$(NAME))

# Colors for pretty output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
CYAN := \033[0;36m
WHITE := \033[1;37m
NC := \033[0m # No Color

# =============================================================================
# Help
# =============================================================================

help: ## Show this help message
	@echo "$(CYAN)Terraform/Atmos Infrastructure Makefile$(NC)"
	@echo "$(WHITE)========================================$(NC)"
	@echo
	@echo "$(WHITE)Current Configuration:$(NC)"
	@echo "  TENANT:      $(GREEN)"$(call sq,$(TENANT))"$(NC)"
	@echo "  STAGE:       $(GREEN)"$(call sq,$(STAGE))"$(NC)"
	@echo "  ENVIRONMENT: $(GREEN)"$(call sq,$(ENVIRONMENT))"$(NC)"
	@echo "  REGION:      $(GREEN)"$(call sq,$(REGION))"$(NC)"
	@echo "  STACK:       $(GREEN)"$(call sq,$(STACK))"$(NC)"
	@echo
	@echo "$(WHITE)Available Commands:$(NC)"
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*?##/ { printf "  $(CYAN)%-30s$(NC) %s\n", $$1, $$2 }' $(MAKEFILE_LIST) | sort
	@echo
	@echo "$(WHITE)Quick Examples:$(NC)"
	@echo "  $(GREEN)make validate STAGE=prod$(NC)"
	@echo "  $(GREEN)make plan-component COMPONENT=vpc/main$(NC)"
	@echo "  $(GREEN)make sweep STACK=fnx-ue1-dev$(NC)"
	@echo "  $(GREEN)atmos list workflows$(NC)   # every Atmos workflow"

# =============================================================================
# Core Infrastructure Commands
# =============================================================================

lint: ## Lint and format all code
	@echo "$(BLUE)Linting and formatting code...$(NC)"
	@atmos workflow lint -f lint

validate: ## Validate all Terraform configurations
	@echo "$(BLUE)Validating configurations for "$(call sq,$(STACK))"...$(NC)"
	@atmos workflow validate -f validate -s $(call sq,$(STACK))

validate-all: ## Validate all available stacks
	@echo "$(CYAN)🔍 Validating all stacks...$(NC)"
	@atmos workflow validate-all -f validate-enhanced

sweep: ## Plan the stack's pairs against its resolved variables, no AWS (atmos sweep)
	@atmos sweep -s $(call sq,$(STACK))

plan: ## Plan infrastructure changes
	@echo "$(BLUE)Planning infrastructure changes for "$(call sq,$(STACK))"...$(NC)"
	@atmos workflow plan -f plan-environment -s $(call sq,$(STACK))

apply: ## Apply infrastructure changes (with confirmation)
	@echo "$(YELLOW)⚠️  This will apply changes to "$(call sq,$(STACK))"!$(NC)"
	@read -p "Are you sure? (y/N) " -n 1 -r; \
	echo; \
	if [ "$$REPLY" = "y" ] || [ "$$REPLY" = "Y" ]; then \
		echo "$(BLUE)Applying infrastructure changes...$(NC)"; \
		atmos workflow apply -f apply-environment -s $(call sq,$(STACK)); \
	else \
		echo "$(YELLOW)Apply cancelled.$(NC)"; \
	fi

destroy: ## Destroy infrastructure (the workflow asks for the stack name twice)
	@echo "$(RED)⚠️  DANGER: This destroys every component of the stack you type (e.g. "$(call sq,$(STACK))")!$(NC)"
	@atmos workflow destroy -f destroy-environment

status: ## Show the components of the current stack
	@echo "$(WHITE)Infrastructure Status for "$(call sq,$(STACK))"$(NC)"
	@echo "================================================"
	@echo "$(WHITE)Components:$(NC)"
	@atmos list components -s $(call sq,$(STACK)) 2>/dev/null || echo "  No components configured"

drift: ## Check for configuration drift
	@echo "$(BLUE)Checking for configuration drift...$(NC)"
	@atmos workflow drift-detection -f drift-detection -s $(call sq,$(STACK))

plan-component: ## Plan specific component (usage: make plan-component COMPONENT=vpc/main)
	@if [ -z $(call sq,$(COMPONENT)) ]; then \
		echo "$(RED)Error: COMPONENT variable is required$(NC)"; \
		echo "Usage: make plan-component COMPONENT=vpc/main"; \
		exit 1; \
	fi
	@echo "$(BLUE)Planning "$(call sq,$(COMPONENT))" changes...$(NC)"
	@atmos terraform plan $(call sq,$(COMPONENT)) -s $(call sq,$(STACK))

apply-component: ## Apply specific component (usage: make apply-component COMPONENT=vpc/main)
	@if [ -z $(call sq,$(COMPONENT)) ]; then \
		echo "$(RED)Error: COMPONENT variable is required$(NC)"; \
		echo "Usage: make apply-component COMPONENT=vpc/main"; \
		exit 1; \
	fi
	@echo "$(BLUE)Applying "$(call sq,$(COMPONENT))" changes...$(NC)"
	@atmos terraform apply $(call sq,$(COMPONENT)) -s $(call sq,$(STACK))

list-stacks: ## List all available stacks
	@atmos list stacks

# =============================================================================
# Environment Management
# =============================================================================

# Stage stacks come from the stack scaffold (scaffolds/stack; docs/OPERATIONS.md,
# "Adding a stack"), run from the repository root with target `.`. ANSWERS is a
# key=value file of its answers (copy a scaffolds/stack-golden/*.env and edit
# it); `make onboard` without one prompts for every answer. TENANT, STAGE,
# REGION and the default CIDRs go first, so the file's answers win over them;
# onboard-custom's VPC_CIDR and VPC_CIDR_SERVICES go last and win over the file.
# Lanes (NAME) are not scaffolded: copy a templates/stacks sample.
# scripts/scaffold-stack.sh reads the file line by line, refuses any line it
# cannot pass as one --set word (naming it), and runs the scaffold; make never
# pastes the file's contents into a shell, and passes its own values through sq.
ANSWERS ?=
VPC_CIDR_SERVICES ?=
SCAFFOLD_STACK = bash scripts/scaffold-stack.sh
SCAFFOLD_SET = --set $(call sq,tenant=$(TENANT)) --set $(call sq,stage=$(STAGE)) --set $(call sq,region=$(REGION)) --set $(call sq,region_code=$(ENVIRONMENT))

onboard: ## Generate a stage stack with the stack scaffold (ANSWERS=<key=value file>; without it, prompts)
	@echo "$(BLUE)Generating a stack with the stack scaffold...$(NC)"
	$(SCAFFOLD_STACK)$(if $(ANSWERS), $(SCAFFOLD_SET) --set vpc_cidr_main=10.0.0.0/16 --set vpc_cidr_services=10.1.0.0/16 --answers $(call sq,$(ANSWERS)))

onboard-custom: ## Like onboard, with your CIDRs (usage: make onboard-custom ANSWERS=my.env VPC_CIDR=10.22.0.0/16 [VPC_CIDR_SERVICES=10.23.0.0/16])
	@if [ -z $(call sq,$(VPC_CIDR)) ] || [ -z $(call sq,$(ANSWERS)) ]; then \
		echo "$(RED)Error: ANSWERS and VPC_CIDR are required$(NC)"; \
		echo "Usage: make onboard-custom ANSWERS=my.env VPC_CIDR=10.22.0.0/16 [VPC_CIDR_SERVICES=10.23.0.0/16]"; \
		exit 1; \
	fi
	@echo "$(BLUE)Generating a stack with the stack scaffold and your CIDRs...$(NC)"
	$(SCAFFOLD_STACK) $(SCAFFOLD_SET) --answers $(call sq,$(ANSWERS)) --set $(call sq,vpc_cidr_main=$(VPC_CIDR))$(if $(VPC_CIDR_SERVICES), --set $(call sq,vpc_cidr_services=$(VPC_CIDR_SERVICES)))

# =============================================================================
# AWS Backend Setup and Management
# =============================================================================
# US state lives in one S3 bucket, <tenant>-terraform-state (native lockfile
# locking, no DynamoDB), created and managed by backend/main in the management
# account's stack fnx-ue1-root (BACKEND_STACK=fnx-ew1-root: the EU stacks' bucket,
# fnx-ew1-terraform-state). First creation: make setup-aws-backend-cold-start.

BACKEND_STACK ?= fnx-ue1-root

setup-aws-backend-cold-start: ## Create a state backend (BACKEND_STACK; once, management-account admin credentials)
	@echo "$(BLUE)Creating the state backend in "$(call sq,$(BACKEND_STACK))"...$(NC)"
	@atmos workflow backend-cold-start -f bootstrap -s $(call sq,$(BACKEND_STACK))

setup-aws-backend: ## Plan and apply a state backend (backend/main in BACKEND_STACK, default fnx-ue1-root)
	@echo "$(BLUE)Updating the state backend in "$(call sq,$(BACKEND_STACK))"...$(NC)"
	@atmos workflow backend-only -f bootstrap -s $(call sq,$(BACKEND_STACK))

setup-aws-backend-dry-run: ## Show the backend configuration and plan without applying
	@atmos terraform backend describe backend/main -s $(call sq,$(BACKEND_STACK))
	@atmos terraform plan backend/main -s $(call sq,$(BACKEND_STACK))

validate-aws-setup: ## Validate the existing state backend
	@echo "$(BLUE)Validating the state backend in "$(call sq,$(BACKEND_STACK))"...$(NC)"
	@atmos workflow verify -f bootstrap -s $(call sq,$(BACKEND_STACK))

# Steps 2 and 3 call atmos directly: a nested $(MAKE) ... STACK=<value> would
# make the child re-expand the value as make syntax ($(shell ...) would run).
bootstrap-environment: ## Complete environment bootstrap (IAM + VPCs, backend check, validation)
	@echo "$(BLUE)Bootstrapping complete environment: "$(call sq,$(STACK))"$(NC)"
	@echo "Step 1/3: IAM (CI roles) and networking (needs the state backend: make setup-aws-backend-cold-start)..."
	@atmos workflow full -f bootstrap -s $(call sq,$(STACK))
	@echo
	@echo "Step 2/3: Validating backend setup..."
	@atmos workflow verify -f bootstrap -s $(call sq,$(BACKEND_STACK))
	@echo
	@echo "Step 3/3: Running configuration validation..."
	@atmos workflow validate -f validate -s $(call sq,$(STACK))
	@echo
	@echo "$(GREEN)✅ Environment bootstrap completed successfully!$(NC)"
	@echo "Next steps:"
	@echo "  1. Plan infrastructure: make plan STACK="$(call sq,$(STACK))
	@echo "  2. Deploy layer by layer: atmos workflow deploy -f deploy-full-stack -s "$(call sq,$(STACK))

cleanup-aws-backend: ## Destroy the backend/main component (DANGEROUS; the workflow asks for confirmation)
	@echo "$(RED)⚠️  WARNING: This destroys the Terraform state backend component!$(NC)"
	@atmos workflow destroy -f destroy-backend

# =============================================================================
# Operations and Utilities
# =============================================================================

check-security: ## Run security checks (Trivy + Checkov via the security-scan workflow)
	@echo "$(BLUE)Running security checks...$(NC)"
	@atmos workflow security-scan -f lint
	@echo "$(GREEN)✅ Security check complete$(NC)"

import-resource: ## Import existing resource into Terraform state
	@echo "$(BLUE)Starting resource import workflow...$(NC)"
	@atmos workflow import -f import -s $(call sq,$(STACK))

rotate-certs: ## Rotate SSL certificates
	@echo "$(BLUE)Rotating SSL certificates...$(NC)"
	@atmos workflow rotate -f rotate-certificate

state-ops: ## Perform state operations
	@echo "$(BLUE)Starting state operations workflow...$(NC)"
	@STACK=$(call sq,$(STACK)) atmos workflow list-locks -f state-operations

clean: ## Clean temporary files and caches
	@echo "$(BLUE)Cleaning temporary files...$(NC)"
	@find . -name "*.tfplan" -delete
	@find . -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null || true
	@find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
	@find . -name "*.pyc" -delete 2>/dev/null || true
	@echo "$(GREEN)✅ Cleanup complete$(NC)"

update-docs: ## Regenerate component README docs (terraform-docs pre-commit hook)
	@echo "$(BLUE)Updating documentation...$(NC)"
	@pre-commit run terraform_docs --all-files
