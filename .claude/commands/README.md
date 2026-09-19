# Claude Commands for Terraform/Atmos Infrastructure

This directory contains Claude-specific command shortcuts for common infrastructure development workflows. These are optimized for Claude Code usage but can be referenced by developers as well.

## Available Commands

### 🔍 **Status & Diagnostics**
- [`check-infrastructure-status.md`](check-infrastructure-status.md) - Get comprehensive infrastructure status
- [`troubleshoot-common-issues.md`](troubleshoot-common-issues.md) - Solutions for frequent problems

### ✅ **Validation & Planning** 
- [`validate-infrastructure.md`](validate-infrastructure.md) - Validate configurations safely
- [`plan-infrastructure-changes.md`](plan-infrastructure-changes.md) - Preview changes before applying

### 🚀 **Deployment & Management**
- [`apply-infrastructure-changes.md`](apply-infrastructure-changes.md) - Apply changes to infrastructure
- [`onboard-new-environment.md`](onboard-new-environment.md) - Create new environments

### 🐳 **Development Environment**
- [`start-development-environment.md`](start-development-environment.md) - Start local development stack

## Usage in Claude Code

When working with Claude Code, you can reference these commands:

```
"Help me validate the infrastructure" 
→ Claude will reference validate-infrastructure.md

"I need to troubleshoot an AWS credential issue"
→ Claude will reference troubleshoot-common-issues.md

"How do I plan infrastructure changes safely?"
→ Claude will reference plan-infrastructure-changes.md
```

## Command Structure

Each command file includes:
- **What this does** - Clear explanation of the command's purpose
- **Commands to run** - Specific bash commands with examples
- **Expected output** - What you should see when successful
- **Troubleshooting** - Common issues and solutions
- **Safety notes** - Important warnings for destructive operations

## Quick Reference

### Most Used Commands
```bash
make doctor          # System diagnostics
make status          # Infrastructure status
make validate        # Validate configurations
make plan           # Preview changes (safe)
make apply          # Apply changes (with confirmation)
./scripts/quickstart.sh # Interactive getting started guide
```

### Emergency Commands
```bash
make doctor                    # Diagnose issues
make api-health                # Check Atmos and its configuration load
make dev-reset               # Reset development environment
aws sts get-caller-identity  # Check AWS credentials
```

### Development Workflow
1. `make status` - Check current state
2. Make your infrastructure changes
3. `make validate` - Ensure configurations are valid
4. `make plan` - Review what will change
5. `make apply` - Apply changes (with confirmation)
6. `make status` - Verify final state

## Integration with Main Tooling

These commands integrate with:
- **Makefile** - Main task runner with shortcuts
- **Atmos** - Core infrastructure orchestration tool
- **Terraform** - Infrastructure as code engine

## Customization

You can customize these commands by:
1. Editing the markdown files directly
2. Adding new command files following the same structure
3. Updating the main Makefile to include new shortcuts
4. Adding new Atmos workflows in `workflows/*.yaml`

## Support

For issues or questions:
1. Start with `make doctor` for system diagnostics
2. Check `troubleshoot-common-issues.md` for common solutions
3. Review logs in the `logs/` directory
4. Consult the main documentation in `docs/`