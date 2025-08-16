# Terminal Power User Guide

**Gaia** - Terminal-First Infrastructure Management Platform

## 🎯 Philosophy

This platform embraces the terminal as the ultimate power tool for infrastructure management. No GUIs, no complex dashboards - just powerful CLI tools and REST APIs that work exactly how grown-ups expect them to.

## 🚀 Quick Start

### 1. Install Gaia CLI
```bash
cd gaia
pip install -e .
```

### 2. Start the API Server
```bash
# Terminal 1: Start the API server
gaia serve --port 8080

# Terminal 2: Use the API
curl http://localhost:8080/stacks
```

### 3. Power User Shortcuts
```bash
# Add to your ~/.bashrc or ~/.zshrc
make shell-functions >> ~/.bashrc
source ~/.bashrc

# Now you have shortcuts:
gaia-status           # Quick infrastructure status
gaia-validate         # Validate infrastructure
gaia-lint            # Lint configurations
tf-plan vpc          # Plan a specific component
```

## 🔧 Core Tools

### Gaia CLI - Enhanced Developer Experience
```bash
# Interactive workflows
gaia workflow validate --tenant fnx --account dev --environment testenv-01
gaia workflow plan-environment --tenant fnx --account dev --environment testenv-01
gaia quick-start     # New developer onboarding
gaia doctor         # System diagnostics

# Direct Terraform operations
gaia terraform plan vpc --stack fnx-dev-testenv-01
gaia terraform validate vpc --stack fnx-dev-testenv-01

# Utilities
gaia status         # Infrastructure overview
gaia describe stacks
gaia list components --stack fnx-dev-testenv-01
```

### REST API - Terminal-First Integration
```bash
# Basic operations
curl http://localhost:8080/stacks                    # List stacks
curl http://localhost:8080/components               # List components
curl http://localhost:8080/health                   # Health check

# Validation & Operations
curl -X POST http://localhost:8080/validate         # Validate all
curl -X POST http://localhost:8080/lint             # Lint all
curl -X POST http://localhost:8080/stacks/fnx-dev-testenv-01/validate

# Workflow execution
curl -X POST -H "Content-Type: application/json" \
     -d '{"tenant":"fnx","account":"dev","environment":"testenv-01"}' \
     http://localhost:8080/workflows/validate

# Component operations
curl -X POST -H "Content-Type: application/json" \
     -d '{"stack":"fnx-dev-testenv-01"}' \
     http://localhost:8080/components/vpc/validate
```

### Makefile - Power User Commands
```bash
# Enhanced development workflows
make help           # Show all commands with examples
make quick-health   # Comprehensive system check
make dev-cycle      # lint -> validate -> plan
make safety-check   # Pre-apply safety validation

# API integration
make api-serve      # Start API server
make api-status     # Infrastructure status via API
make api-lint       # Lint via API
make watch-api-status  # Continuous monitoring

# Batch operations
make validate-all   # Validate all stacks
make component-info COMPONENT=vpc  # Component details

# Terminal ergonomics
make show-config    # Show current configuration
make shell-functions  # Generate bash functions
```

### Manifest Generation & Templating
```bash
# Generate infrastructure manifests
./scripts/manifest-generator.sh stack fnx-dev-testenv-01
./scripts/manifest-generator.sh component vpc

# Create new infrastructure from templates  
./scripts/manifest-generator.sh template stack my-new-stack
./scripts/manifest-generator.sh template component my-service
./scripts/manifest-generator.sh resource aws_s3_bucket

# List available templates
./scripts/manifest-generator.sh list
```

## 💡 Power User Patterns

### 1. Continuous Monitoring
```bash
# Watch mode for real-time status
make watch-validate     # Continuous validation
make watch-api-status   # API-based monitoring
watch -n 30 'gaia-status'  # Custom watch interval
```

### 2. Batch Operations
```bash
# Validate all stacks in parallel
for stack in $(curl -s http://localhost:8080/stacks | jq -r '.stacks[]'); do
  echo "Validating $stack..."
  curl -X POST http://localhost:8080/stacks/$stack/validate | jq '.summary' &
done
wait
```

### 3. JSON Processing Workflows
```bash
# Get only failed validations
curl -X POST http://localhost:8080/stacks/fnx-dev-testenv-01/validate | \
  jq '.results[] | select(.success == false)'

# Component health dashboard
curl -s http://localhost:8080/status | jq '{
  total_stacks: .summary.total_stacks,
  atmos_ok: .summary.atmos_available,
  in_project: .summary.in_project
}'
```

### 4. CI/CD Integration
```bash
# GitHub Actions example
- name: Infrastructure Validation
  run: |
    gaia serve --port 8080 &
    sleep 5
    
    RESULT=$(curl -X POST http://localhost:8080/validate)
    SUCCESS=$(echo $RESULT | jq -r '.success')
    
    if [ "$SUCCESS" != "true" ]; then
      echo "❌ Validation failed"
      exit 1
    fi
```

### 5. Error Handling & Retry Logic
```bash
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
```

## 📊 Advanced Features

### API Documentation & Examples
```bash
# Interactive examples
./scripts/curl-examples.sh                    # Show all examples
./scripts/curl-examples.sh list-stacks       # Run specific example
./scripts/curl-examples.sh validate-stack    # Validate example

# Get complete API documentation
curl http://localhost:8080/ | jq '.'
```

### Shell Integration
```bash
# Add these functions to your shell profile
source <(make shell-functions)

# Now you have powerful shortcuts:
gaia-quick         # Show available commands
gaia-status        # Infrastructure status
gaia-validate      # Validate default stack
gaia-validate production-stack  # Validate specific stack
tf-plan vpc        # Plan VPC component
infra-status       # Alias for make quick-health
```

### Development Workflows
```bash
# Component development cycle
make dev-cycle-component COMPONENT=vpc
# 1. Shows component info
# 2. Runs linting
# 3. Validates component
# 4. Plans component changes

# Full environment workflow
make dev-cycle TENANT=fnx ENVIRONMENT=prod
# 1. Lint all configurations
# 2. Validate all components
# 3. Plan all changes
```

## 🛡️ Safety & Best Practices

### Pre-Apply Safety Checks
```bash
# Comprehensive safety validation
make safety-check
# ✅ Configuration validation
# ✅ AWS credentials check
# ✅ Terraform version check
# ✅ Atmos version check
# ✅ State backend check
```

### Monitoring & Alerting
```bash
# Health monitoring script for cron
#!/bin/bash
API_BASE="http://localhost:8080"

# Check API health
if ! curl -f -s $API_BASE/health > /dev/null; then
  echo "🚨 Gaia API server is down!"
  # Send alert to Slack/email/PagerDuty
fi

# Check validation status
VALIDATION=$(curl -s -X POST $API_BASE/validate | jq -r '.success')
if [ "$VALIDATION" != "true" ]; then
  echo "⚠️ Infrastructure validation failing"
  # Send alert
fi
```

## 🔧 Customization

### Environment Variables
```bash
export ATMOS_API_PORT=8080        # API server port
export TENANT=fnx                 # Default tenant
export ACCOUNT=dev                # Default account
export ENVIRONMENT=testenv-01     # Default environment
export REGION=eu-west-2           # Default region
```

### Configuration Override
```bash
# Override defaults in Makefile commands
make validate TENANT=production ENVIRONMENT=live
make plan COMPONENT=rds STACK=production-live-prod
make api-validate-stack STACK=production-live-prod
```

## 🎯 Why Terminal-First?

1. **Speed**: No GUI loading times, instant feedback
2. **Automation**: Easy to script and integrate with CI/CD
3. **Precision**: Exact control over every operation
4. **Reproducibility**: Commands can be saved, versioned, shared
5. **Power**: Combine tools with pipes, loops, conditions
6. **Focus**: Terminal keeps you in the flow state

## 📈 Performance

- **API Response Times**: < 100ms for status checks
- **Batch Operations**: Parallel execution where possible  
- **Resource Usage**: Minimal - terminal tools are lightweight
- **Scalability**: Handles hundreds of stacks/components efficiently

---

**Built for developers who understand that the terminal is not a step backwards - it's the step forward that takes you beyond the limitations of clicking.**