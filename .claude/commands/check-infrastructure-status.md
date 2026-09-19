# Check Infrastructure Status

Get a comprehensive overview of your current infrastructure state and recent activity.

## What this shows
- Available environments (stacks) 
- Components deployed in each environment
- Recent workflow activity and logs
- System health and diagnostics
- AWS account and credential status

## Commands to run

### Quick status overview
```bash
make status
```

### Detailed stack status with Atmos
```bash
# General status
atmos list components -s fnx-dev-testenv-01

# Full stack description for a specific environment
atmos describe stacks -s fnx-dev-testenv-01
```

### System diagnostics
```bash
# Full system health check
make doctor
```

### List available environments
```bash
make list-stacks

# Or with friendly names
./scripts/list_stacks.sh
```

### View recent activity
```bash
# View development environment logs
make dev-logs

# Check logs directory
ls -la logs/
```

## Understanding the output

### Stack Status
- Shows your current stack configuration
- Lists all components in each environment
- Displays friendly names (e.g., `fnx-testenv-01-dev`)

### Component Status
Components you might see:
- `vpc` - Virtual Private Cloud (networking foundation)
- `eks` - Elastic Kubernetes Service (container platform)
- `rds` - Relational Database Service
- `iam` - Identity and Access Management (security)
- `monitoring` - Observability and alerting
- `secretsmanager` - Secure secret storage

### Health Indicators
- ✅ Green: Working properly
- ⚠️ Yellow: Warning or needs attention  
- ❌ Red: Error or not working
- 📋 Blue: Information or status

## Troubleshooting

### Common issues and solutions

**No stacks found:**
- Check if you're in the project root directory
- Verify `atmos.yaml` exists
- Run `make doctor` for diagnostics

**AWS credential errors:**
- Run `aws sts get-caller-identity`
- Configure credentials: `aws configure`
- Check AWS_PROFILE environment variable

**Component issues:**
- Check specific component: `make plan-component COMPONENT=vpc`
- Review recent logs in `logs/` directory
- Run validation: `make validate`

### Getting help
- `make help` - Show all available commands
- `atmos --help` - Show Atmos CLI options
- `make doctor` - Run comprehensive diagnostics
- Check `QUICK_START.md` for common tasks