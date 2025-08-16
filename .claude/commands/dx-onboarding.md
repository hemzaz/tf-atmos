# Developer Experience Onboarding Command

## Single Command Infrastructure Setup

This command provides a comprehensive, zero-to-productive developer onboarding experience.

## Usage

```bash
gaia onboard
```

## What it does

1. **Environment Check**: Validates all required tools and dependencies
2. **Project Setup**: Initializes development environment with sensible defaults  
3. **Context Configuration**: Sets up development context for immediate productivity
4. **Guided Tour**: Interactive walkthrough of key workflows
5. **Knowledge Base Setup**: Initializes ChromaDB with project-specific knowledge

## Implementation

The onboarding process uses the task orchestrator to ensure proper dependency resolution and parallel execution where possible.

### Task Flow

```
validate-system → setup-tools → configure-context → initialize-knowledge → guided-tour
      ↓              ↓              ↓                    ↓                  ↓
   Check deps    Install tools   Set defaults      Seed ChromaDB     Interactive guide
```

### Example Output

```
🚀 Welcome to Gaia Infrastructure Platform!

📋 Onboarding Progress:
✅ System validation (2.1s)
✅ Tool setup (45.2s)  
✅ Context configuration (1.3s)
✅ Knowledge base initialization (8.7s)
✅ Guided tour completed

🎯 Your Environment:
  Tenant: fnx
  Account: dev
  Environment: testenv-01
  
💡 Next Steps:
  • Run 'gaia smart "validate my setup"' to verify everything
  • Use 'gaia dashboard' to see system status
  • Try 'gaia smart "deploy to development"' when ready

🎉 You're ready to be productive! 
```

## Intelligent Defaults

The onboarding process establishes intelligent defaults based on:
- Existing project configuration
- Most common usage patterns
- Security best practices
- Performance optimization

## Zero-Configuration Principle

Following the "zero-configuration" principle, the onboarding:
- Detects existing configurations automatically
- Uses sensible defaults for missing values
- Minimizes required user input
- Provides easy customization after initial setup

## Integration Points

- **Makefile**: `make onboard` shortcut
- **Scripts**: Leverages existing `dev-setup.sh` and `onboard-developer.sh`
- **Gaia CLI**: Native `gaia onboard` command
- **Task Orchestrator**: Uses dependency-aware task execution
- **ChromaDB**: Seeds with project-specific knowledge