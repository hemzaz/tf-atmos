# Task Execution Guidelines

## Overview
Comprehensive guidelines for executing Atmos workflows and managing infrastructure tasks safely and efficiently.

## Pre-Execution Checklist

### Environment Preparation
- [ ] **AWS Credentials**: Verify proper AWS credentials are configured
- [ ] **Atmos Version**: Confirm compatible Atmos CLI version (>=1.163.0)
- [ ] **Terraform Version**: Verify Terraform version (>=1.6.0)
- [ ] **Working Directory**: Execute from repository root
- [ ] **Git Status**: Ensure working directory is clean
- [ ] **Network Access**: Confirm connectivity to AWS and required services

### Parameter Validation
- [ ] **Required Parameters**: All required parameters provided
- [ ] **Parameter Format**: Parameters follow naming conventions
- [ ] **Resource Limits**: Check against account/region limits
- [ ] **CIDR Conflicts**: Verify network CIDR allocations
- [ ] **Naming Conflicts**: Ensure unique resource names

## Workflow Execution Patterns

### Standard Execution Flow
```bash
# 1. Validation Phase
atmos workflow validate -f validate.yaml tenant=fnx account=dev environment=testenv-01

# 2. Quality Assurance Phase  
atmos workflow lint -f lint.yaml
atmos workflow compliance-check -f compliance-check.yaml tenant=fnx account=dev environment=testenv-01

# 3. Planning Phase
atmos workflow plan-environment -f plan-environment.yaml tenant=fnx account=dev environment=testenv-01

# 4. Execution Phase (with approval)
atmos workflow apply-environment -f apply-environment.yaml tenant=fnx account=dev environment=testenv-01
```

### Emergency Procedures
```bash
# State Lock Issues
atmos workflow state-operations -f state-operations.yaml tenant=fnx account=dev environment=testenv-01 operation=unlock

# Drift Detection
atmos workflow drift-detection -f drift-detection.yaml tenant=fnx account=dev environment=testenv-01

# Resource Import  
atmos workflow import -f import.yaml tenant=fnx account=dev environment=testenv-01 component=vpc resource_type=aws_vpc resource_id=vpc-12345
```

## Safety Protocols

### Pre-Production Safety
1. **Dry Run Validation**: Always run with `--dry-run` flag when available
2. **Resource Tagging**: Verify all resources have proper tags
3. **Backup Verification**: Confirm backups exist for stateful resources
4. **Rollback Planning**: Document rollback procedures before changes
5. **Change Windows**: Execute during approved maintenance windows

### Production Safety
1. **Change Control**: Production changes require approval workflow
2. **Blue-Green Strategy**: Use blue-green deployments where possible  
3. **Canary Releases**: Gradual rollout for application changes
4. **Monitoring**: Real-time monitoring during deployment
5. **Automated Rollback**: Configure automatic rollback triggers

### Error Handling
```bash
# Check workflow execution status
echo $?  # 0 = success, non-zero = failure

# Resume from specific step
atmos workflow apply-environment -f apply-environment.yaml --from-step step-name

# Manual cleanup after failure
atmos workflow state-operations -f state-operations.yaml operation=unlock
```

## Environment-Specific Guidelines

### Development Environment
**Characteristics:**
- Cost-optimized resources
- Relaxed security policies
- Spot instances allowed
- Automatic shutdown enabled

**Execution Pattern:**
```bash
# Quick iteration cycle
validate → apply-environment
```

**Safety Level:** Low - Allow experimentation

### Staging Environment  
**Characteristics:**
- Production-like configuration
- Full security policies
- On-demand instances
- Manual shutdown only

**Execution Pattern:**
```bash
# Full validation cycle
compliance-check → validate → lint → plan-environment → apply-environment
```

**Safety Level:** Medium - Require validation

### Production Environment
**Characteristics:**
- High availability configuration
- Maximum security policies
- Reserved instances preferred
- 24/7 operations

**Execution Pattern:**
```bash
# Maximum safety cycle
drift-detection → compliance-check → validate → plan-environment → manual-approval → apply-environment → post-validation
```

**Safety Level:** High - Require approvals

## Component-Specific Guidelines

### Network Components (VPC, Subnets, Security Groups)
**Pre-Execution:**
- Validate CIDR block allocations
- Check for IP address conflicts
- Verify routing requirements
- Confirm DNS resolution needs

**Execution:**
- Deploy VPC first
- Create subnets in dependency order
- Apply security groups last
- Validate connectivity after deployment

**Post-Execution:**
- Test network connectivity
- Verify DNS resolution
- Validate security group rules
- Document network topology

### Compute Components (EKS, EC2, Lambda)
**Pre-Execution:**
- Verify network infrastructure exists
- Check instance type availability
- Validate IAM roles and policies
- Confirm image/AMI accessibility

**Execution:**
- Deploy in dependency order
- Monitor resource creation
- Validate health checks
- Configure monitoring and logging

**Post-Execution:**
- Verify service availability
- Test application connectivity
- Monitor resource utilization
- Update documentation

### Data Components (RDS, ElastiCache, S3)
**Pre-Execution:**
- Plan backup strategies
- Verify encryption requirements
- Check compliance policies
- Validate network access

**Execution:**
- Create with encryption enabled
- Configure backup policies
- Set up monitoring
- Apply access controls

**Post-Execution:**
- Verify backup functionality
- Test data access
- Monitor performance
- Document recovery procedures

## Monitoring and Alerting

### Execution Monitoring
- **Start Time**: Record workflow start timestamp
- **Progress Tracking**: Monitor step completion
- **Resource Creation**: Track resource provisioning
- **Error Detection**: Immediate notification of failures
- **Completion Status**: Success/failure reporting

### Performance Monitoring
- **Execution Duration**: Track workflow timing
- **Resource Utilization**: Monitor AWS resource usage
- **Cost Tracking**: Monitor deployment costs
- **Efficiency Metrics**: Measure automation effectiveness

### Alert Configuration
```bash
# Critical Alerts (Immediate Response)
- Workflow failure in production
- Security policy violations
- Resource quota exceeded
- State corruption detected

# Warning Alerts (24-hour Response)
- Drift detection findings
- Certificate expiration warnings
- Resource utilization thresholds
- Backup failure notifications

# Information Alerts (Weekly Review)
- Successful deployments
- Cost optimization opportunities
- Compliance status reports
- Performance metrics
```

## Troubleshooting Guide

### Common Issues

#### State Lock Problems
**Symptoms:** "Resource locked" errors
**Resolution:**
```bash
atmos workflow state-operations -f state-operations.yaml operation=unlock
```

#### Resource Conflicts
**Symptoms:** "Resource already exists" errors
**Resolution:**
```bash
atmos workflow import -f import.yaml resource_type=aws_vpc resource_id=existing-id
```

#### Permission Errors
**Symptoms:** "Access denied" errors
**Resolution:**
- Verify IAM roles and policies
- Check cross-account trust relationships
- Validate MFA requirements
- Confirm resource-based policies

#### Network Connectivity
**Symptoms:** "Connection timeout" errors
**Resolution:**
- Verify VPC configuration
- Check security group rules
- Validate route tables
- Confirm NAT gateway functionality

### Diagnostic Commands
```bash
# Check Atmos configuration
atmos validate stacks

# Verify AWS connectivity
aws sts get-caller-identity

# Check Terraform state
atmos terraform show -s stack-name

# Validate network connectivity
atmos terraform plan vpc -s stack-name
```

## Best Practices

### Code Quality
1. **Validation First**: Always validate before applying
2. **Incremental Changes**: Make small, focused changes
3. **Version Control**: Track all configuration changes
4. **Code Reviews**: Peer review for production changes
5. **Testing**: Test in lower environments first

### Operational Excellence
1. **Documentation**: Document all procedures
2. **Automation**: Automate repetitive tasks
3. **Monitoring**: Implement comprehensive monitoring
4. **Backup**: Regular backup verification
5. **Recovery**: Test disaster recovery procedures

### Security
1. **Least Privilege**: Minimum required permissions
2. **Encryption**: Encrypt data at rest and in transit
3. **Access Logging**: Log all access and changes
4. **Compliance**: Regular compliance validation
5. **Incident Response**: Defined response procedures

### Cost Optimization
1. **Resource Rightsizing**: Match resources to workload
2. **Spot Instances**: Use spot instances where appropriate
3. **Lifecycle Management**: Implement data lifecycle policies
4. **Reserved Capacity**: Plan reserved instance purchases
5. **Cost Monitoring**: Regular cost review and optimization

## Performance Optimization

### Workflow Optimization
- **Parallel Execution**: Run independent tasks in parallel
- **Caching**: Cache frequently used data
- **Batch Operations**: Group related operations
- **Resource Pooling**: Reuse resources where possible

### Resource Optimization
- **Auto Scaling**: Configure appropriate scaling policies
- **Load Balancing**: Distribute traffic efficiently
- **Content Delivery**: Use CDN for static content
- **Database Optimization**: Optimize queries and indexes

## Compliance and Governance

### Audit Requirements
- All workflow executions must be logged
- Change approvals must be documented
- Resource access must be tracked
- Compliance reports must be generated

### Change Management
- All production changes require approval
- Emergency changes need post-facto review
- Change impact must be assessed
- Rollback procedures must be documented

### Risk Management
- Risk assessment for major changes
- Security impact evaluation
- Performance impact analysis
- Business continuity planning