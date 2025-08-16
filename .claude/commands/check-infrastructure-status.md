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

### Enhanced status with Gaia
```bash
# General status
gaia status

# Status for specific environment
gaia status --tenant fnx --account dev --environment testenv-01
```

### System diagnostics
```bash
# Full system health check
make doctor

# Or with Gaia CLI
gaia doctor
```

### List available environments
```bash
make list-stacks

# Or with friendly names
gaia list stacks
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
- `gaia --help` - Show Gaia CLI options
- `make doctor` - Run comprehensive diagnostics
- Check `QUICK_START.md` for common tasks