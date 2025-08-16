# Terminal-First Infrastructure Deployment Guide

## Overview

This guide provides a comprehensive deployment strategy for terminal-first infrastructure management using Atmos and Gaia. The architecture emphasizes command-line workflows, API-driven automation, and developer productivity through power-user tools rather than GUI interfaces.

## Architecture Components

### 1. Local Development Environment

**Location**: `/docker-compose.yml` and `/docker-compose.override.yml`

**Features:**
- Single-command setup (`docker-compose up`)
- Hot reloading for development workflow
- Pre-configured with sample data and monitoring stack
- Resource-efficient for laptop development
- Easy plugin development and testing
- Local authentication bypass for development

**Key Services:**
- Gaia CLI with REST API server (port 8080)
- Terraform and Atmos for infrastructure management
- Terminal-based workflows and validation
- curl-based API interactions
- Manifest generation and templating
- Real-time infrastructure monitoring via API

**Quick Start:**
```bash
# Install Gaia CLI
cd gaia && pip install -e .

# Start API server for terminal integration
gaia serve --port 8080

# Validate infrastructure
gaia workflow validate

# Interactive examples
./scripts/curl-examples.sh

# Generate infrastructure from templates
./scripts/manifest-generator.sh list
```

### 2. Kubernetes Deployment (Optional)

For organizations requiring Kubernetes deployment, components can be deployed using standard Kubernetes manifests or Helm charts generated from Terraform outputs.

**Features:**
- Auto-scaling based on load (HPA)
- High availability with multi-replica deployments
- Multi-region deployment capability
- Comprehensive health checks and probes

**Key Components:**
- Application services with auto-scaling
- Database services with multi-AZ support
- Redis cluster with high availability
- Service mesh integration (optional)
- External Secrets Operator integration

### 3. Infrastructure as Code

**Location**: `/components/terraform/idp-platform/`

**Features:**
- Complete AWS infrastructure provisioning
- EKS cluster with managed node groups
- RDS PostgreSQL with encryption and backups
- ElastiCache Redis cluster
- S3 buckets for storage needs
- Route53 DNS and ACM certificates
- Load balancers and security groups

**Key Resources:**
- EKS cluster with spot and on-demand node groups
- RDS Multi-AZ PostgreSQL with automated backups
- ElastiCache Redis with clustering
- Application Load Balancer with SSL termination
- S3 buckets for artifacts, backups, logs, and techdocs
- CloudWatch monitoring and SNS alerting

**Deployment with Atmos:**
```bash
# Plan infrastructure changes
atmos terraform plan idp-platform -s prod-us-east-1-prod

# Apply infrastructure changes
atmos terraform apply idp-platform -s prod-us-east-1-prod
```

### 4. CI/CD Pipeline

**Location**: `/.github/workflows/`

**Features:**
- Multi-environment promotion (dev -> staging -> prod)
- Automated testing (unit, integration, e2e)
- Comprehensive security scanning
- Container image vulnerability scanning
- Automated database migrations
- Feature flag management
- Rollback capabilities

**Pipeline Stages:**
1. **Code Quality & Security** - Linting, SAST, dependency scanning
2. **Testing** - Unit tests, integration tests with real databases
3. **Build & Push** - Multi-platform container builds with signing
4. **E2E Testing** - Full platform testing in kind cluster
5. **Infrastructure Deployment** - Terraform/Atmos deployment
6. **Application Deployment** - Helm-based Kubernetes deployment

**Workflow Triggers:**
- Push to main/develop branches
- Pull requests
- Release tags
- Scheduled security scans

### 5. Monitoring and Observability

**Features:**
- CloudWatch metrics and logs
- Application performance monitoring
- Infrastructure monitoring
- Custom dashboards and alerting
- Distributed tracing capabilities
- Log aggregation and analysis

**Key Components:**
- CloudWatch dashboards for application metrics
- Infrastructure resource utilization monitoring
- Security and compliance dashboards
- Custom application metrics

**Alerting Rules:**
- Service availability alerts
- Performance degradation alerts
- Security incident alerts
- Infrastructure resource alerts

### 6. Security Implementation

**Location**: `/security/`

**Features:**
- Network security policies (ingress/egress rules)
- RBAC with fine-grained permissions
- Secrets management with External Secrets Operator
- HashiCorp Vault integration
- Pod security standards enforcement
- Istio service mesh with mTLS

**Security Components:**
- Network policies for micro-segmentation
- Service account roles with minimal permissions
- External secrets integration with AWS Secrets Manager/Vault
- Pod Security Policies/Standards
- Istio authorization policies

### 7. Backup and Disaster Recovery

**Location**: `/scripts/dr/`

**Features:**
- Automated backup procedures
- Cross-region backup replication
- Point-in-time recovery capabilities
- Disaster recovery automation
- Comprehensive recovery testing

**Backup Types:**
- **Database Backups** - PostgreSQL and Redis with encryption
- **Kubernetes Backups** - Velero with volume snapshots
- **Configuration Backups** - All Kubernetes configurations
- **Application Backups** - User data and artifacts

**Recovery Procedures:**
- Application-level failure recovery
- Database corruption recovery
- Complete cluster disaster recovery
- Multi-region failover procedures

## Deployment Strategies

### 1. Development Workflow

```bash
# 1. Set up local development
./scripts/dev-setup.sh
./scripts/start-dev.sh

# 2. Develop and test locally
# Code changes are hot-reloaded
# Access services at localhost:3000, localhost:8000

# 3. Run tests
docker-compose exec backstage yarn test
docker-compose exec platform-api pytest

# 4. Create pull request
# CI/CD pipeline runs automatically
```

### 2. Staging Deployment

```bash
# 1. Infrastructure deployment (via CI/CD or manual)
atmos terraform apply idp-platform -s staging-us-east-1-staging

# 2. Application deployment
helm upgrade --install idp-platform-staging k8s/helm/idp-platform \
  --namespace idp-staging --create-namespace \
  --values k8s/helm/idp-platform/values-staging.yaml

# 3. Run integration tests
./tests/integration/run-tests.sh --environment=staging
```

### 3. Production Deployment

```bash
# 1. Blue-Green Deployment
kubectl create namespace idp-production-green

# 2. Deploy to green environment
helm upgrade --install idp-platform-green k8s/helm/idp-platform \
  --namespace idp-production-green \
  --values k8s/helm/idp-platform/values-production.yaml

# 3. Run smoke tests
./tests/smoke/run-tests.sh --environment=production-green

# 4. Switch traffic (via service/ingress update)
kubectl patch service idp-platform-backstage \
  -p '{"spec":{"selector":{"version":"green"}}}'

# 5. Monitor and rollback if needed
kubectl patch service idp-platform-backstage \
  -p '{"spec":{"selector":{"version":"blue"}}}'
```

## Security Hardening

### Network Security
- Default deny-all network policies
- Istio service mesh with mTLS
- Pod security standards enforcement
- Regular security scanning

### Secrets Management
- External Secrets Operator with Vault/AWS Secrets Manager
- Encrypted secrets at rest and in transit
- Regular secret rotation
- Least-privilege access controls

### Access Control
- RBAC with role-based permissions
- Service account authentication
- AWS IAM roles for service accounts (IRSA)
- Multi-factor authentication for administrative access

## Monitoring Strategy

### Application Monitoring
- HTTP request metrics and traces
- Business logic metrics
- User activity tracking
- Performance monitoring

### Infrastructure Monitoring
- Kubernetes cluster health
- Node resource utilization
- Network traffic and policies
- Storage and database performance

### Security Monitoring
- Failed authentication attempts
- Suspicious network activity
- Security policy violations
- Compliance monitoring

## Disaster Recovery

### Recovery Time Objectives (RTOs)
- Application failures: 15 minutes
- Database issues: 1 hour
- Complete cluster loss: 4 hours
- Multi-region disaster: 24 hours

### Recovery Point Objectives (RPOs)
- Application data: 5 minutes
- Database: 15 minutes
- Configuration: 1 hour
- Cross-region: 4 hours

### Testing Schedule
- Monthly DR drills
- Quarterly chaos engineering
- Annual full-scale simulation

## Scaling and Performance

### Auto-scaling Configuration
- **Backstage**: 2-10 replicas based on CPU/memory
- **Platform API**: 3-20 replicas based on request rate
- **Database**: Read replicas for scaling reads
- **Redis**: Cluster mode for horizontal scaling

### Performance Optimization
- CDN for static assets
- Database query optimization
- Caching strategies
- Connection pooling

## Compliance and Governance

### Compliance Standards
- SOC 2 Type II compliance
- GDPR data protection
- HIPAA security controls (if applicable)
- PCI DSS for payment data

### Audit and Logging
- Comprehensive audit logging
- Log retention policies
- Compliance reporting
- Regular security assessments

## Cost Optimization

### Resource Management
- Spot instances for non-critical workloads
- Right-sizing based on usage patterns
- Storage lifecycle policies
- Reserved instances for predictable workloads

### Monitoring and Alerting
- Cost monitoring dashboards
- Budget alerts and controls
- Resource utilization tracking
- Automated cost optimization recommendations

## Getting Started

### Prerequisites
- Docker and Docker Compose
- Kubernetes cluster (local or cloud)
- AWS CLI and credentials
- Terraform and Atmos
- Helm 3.x

### Quick Start
1. **Local Development**: Run `./scripts/dev-setup.sh`
2. **Infrastructure**: Deploy with `atmos terraform apply`
3. **Application**: Deploy with Helm charts
4. **Monitoring**: Configure Prometheus and Grafana
5. **Backup**: Set up Velero and backup procedures

### Support and Documentation
- **Runbooks**: `/scripts/dr/disaster-recovery-playbook.md`
- **Monitoring**: `/monitoring/grafana/dashboards/`
- **Security**: `/security/policies/`
- **Development**: `/platform/backstage/README.md`

---

This deployment architecture provides a production-ready, scalable, and maintainable Internal Developer Platform with comprehensive operational capabilities.