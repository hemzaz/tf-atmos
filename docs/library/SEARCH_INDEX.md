# Alexandria Library Search Index

**Find the Right Component for Any Use Case**

This searchable index helps you quickly locate components by use case, AWS service, cost, complexity, or tags. Think of this as your card catalog to the Library of Alexandria.

---

## Quick Search

### By Common Use Case

| I need to... | Use Component(s) | Documentation |
|--------------|------------------|---------------|
| **Store Terraform state** | backend | [docs](../../components/terraform/backend/) |
| **Create a network** | vpc | [docs](../../components/terraform/vpc/) |
| **Run containers on Kubernetes** | eks + eks-addons | [docs](../../components/terraform/eks/) |
| **Run simple containers** | ecs | [docs](../../components/terraform/ecs/) |
| **Run serverless functions** | lambda | [docs](../../components/terraform/lambda/) |
| **Deploy virtual machines** | ec2 | [docs](../../components/terraform/ec2/) |
| **Host a relational database** | rds | [docs](../../components/terraform/rds/) |
| **Store secrets securely** | secretsmanager | [docs](../../components/terraform/secretsmanager/) |
| **Create an API** | apigateway + lambda | [docs](../../components/terraform/apigateway/) |
| **Manage DNS records** | dns | [docs](../../components/terraform/dns/) |
| **Get SSL certificates** | acm | [docs](../../components/terraform/acm/) |
| **Set up monitoring** | monitoring | [docs](../../components/terraform/monitoring/) |
| **Control network access** | securitygroup | [docs](../../components/terraform/securitygroup/) |
| **Manage user permissions** | iam | [docs](../../components/terraform/iam/) |
| **Backup my data** | backup | [docs](../../components/terraform/backup/) |
| **Scan for security issues** | security-monitoring | [docs](../../components/terraform/security-monitoring/) |
| **Optimize costs** | cost-optimization | [docs](../../components/terraform/cost-optimization/) |

### By Application Type

| Application Type | Recommended Stack | Estimated Cost |
|------------------|-------------------|----------------|
| **Simple Web App** | vpc + ecs + rds + monitoring | $200-400/month |
| **Complex Microservices** | vpc + eks + eks-addons + rds + monitoring | $1,000-2,000/month |
| **Serverless API** | lambda + apigateway + secretsmanager | $50-200/month |
| **Static Website** | dns + acm | $1-10/month |
| **Data Processing Pipeline** | lambda + apigateway + monitoring | $100-500/month |
| **ML Training** | ec2 (GPU) + vpc | $400-2,000/month |
| **Batch Processing** | ec2 (spot) + lambda | $50-300/month |

### By Budget

| Monthly Budget | Recommended Configuration | Components |
|----------------|---------------------------|------------|
| **< $100** | Development, single-tenant | vpc (single NAT) + lambda + secretsmanager |
| **$100-500** | Development/Staging | vpc + ecs + rds (small) + monitoring |
| **$500-2,000** | Production (small) | vpc + eks + rds (multi-AZ) + monitoring + backup |
| **$2,000-5,000** | Production (medium) | Full stack with autoscaling |
| **> $5,000** | Enterprise Production | Multi-region, full redundancy |

---

## Search by AWS Service

### Compute Services

| AWS Service | Component | Use When | Cost Range |
|-------------|-----------|----------|------------|
| **Amazon EKS** | eks | Need Kubernetes, complex orchestration | $$$ |
| **Amazon ECS** | ecs | Containerized apps, simpler than EKS | $$ |
| **AWS Lambda** | lambda | Event-driven, serverless, variable load | $ |
| **Amazon EC2** | ec2 | VMs, legacy apps, specific OS needs | $$ |

### Networking Services

| AWS Service | Component | Use When | Cost Range |
|-------------|-----------|----------|------------|
| **Amazon VPC** | vpc | Always (networking foundation) | $$ |
| **Security Groups** | securitygroup | Always (network firewall) | Free |
| **AWS VPN** | vpc (vpn_gateway) | On-premises connectivity | $ |
| **AWS Transit Gateway** | vpc (tgw_attachment) | Multi-VPC networking | $$ |

### Database Services

| AWS Service | Component | Use When | Cost Range |
|-------------|-----------|----------|------------|
| **Amazon RDS** | rds | Relational databases (PostgreSQL, MySQL) | $$$ |
| **Amazon Aurora** | rds (engine=aurora) | High-performance relational | $$$ |
| **Aurora Serverless** | rds (serverless=true) | Variable database load | $$ |

### Security Services

| AWS Service | Component | Use When | Cost Range |
|-------------|-----------|----------|------------|
| **AWS IAM** | iam | Always (permissions) | Free |
| **AWS Secrets Manager** | secretsmanager | Store sensitive data | $ |
| **AWS Certificate Manager** | acm | SSL/TLS certificates | Free |
| **AWS GuardDuty** | security-monitoring | Threat detection | $$ |
| **AWS Security Hub** | security-monitoring | Security compliance | $$ |

### Monitoring Services

| AWS Service | Component | Use When | Cost Range |
|-------------|-----------|----------|------------|
| **Amazon CloudWatch** | monitoring | Always (metrics and alarms) | $ |
| **AWS X-Ray** | monitoring | Distributed tracing | $ |
| **CloudWatch Logs** | monitoring | Log aggregation | $ |

### Integration Services

| AWS Service | Component | Use When | Cost Range |
|-------------|-----------|----------|------------|
| **Amazon API Gateway** | apigateway | REST/HTTP/WebSocket APIs | $$ |
| **Amazon Route 53** | dns | DNS management | $ |
| **External Secrets Operator** | external-secrets | K8s secrets sync | $ |

### Backup Services

| AWS Service | Component | Use When | Cost Range |
|-------------|-----------|----------|------------|
| **AWS Backup** | backup | Centralized backup management | $$ |
| **S3 (for state)** | backend | Terraform state storage | $ |

---

## Search by Category

### Foundations (4 components)

Essential infrastructure components.

| Component | Purpose | When to Deploy | Cost |
|-----------|---------|----------------|------|
| backend | Terraform state storage | First (always) | $ |
| vpc | Virtual network | Second (always) | $$ |
| iam | Identity and access | Third (always) | Free |
| securitygroup | Network firewall | Fourth (always) | Free |

**Category Guide**: [docs/library/foundations/](./foundations/README.md)

---

### Compute (6 components)

Run your application workloads.

| Component | Purpose | When to Deploy | Cost |
|-----------|---------|----------------|------|
| eks | Kubernetes clusters | Complex microservices | $$$ |
| eks-addons | K8s extensions | With EKS | $$ |
| eks-backend-services | EKS support services | With EKS | $ |
| ecs | Container service | Simpler containers | $$ |
| ec2 | Virtual machines | Traditional apps | $$ |
| lambda | Serverless functions | Event-driven | $ |

**Category Guide**: [docs/library/compute/](./compute/README.md)

---

### Data (3 components)

Store and protect your data.

| Component | Purpose | When to Deploy | Cost |
|-----------|---------|----------------|------|
| rds | Relational databases | Need SQL database | $$$ |
| secretsmanager | Secure secrets | Always (best practice) | $ |
| backup | Data protection | Production (required) | $$ |

**Category Guide**: [docs/library/data/](./data/README.md)

---

### Integration (3 components)

Connect services and expose APIs.

| Component | Purpose | When to Deploy | Cost |
|-----------|---------|----------------|------|
| apigateway | API management | Expose APIs | $$ |
| external-secrets | K8s secrets sync | With EKS | $ |
| dns | Domain management | Need custom domain | $ |

**Category Guide**: [docs/library/integration/](./integration/README.md)

---

### Observability (3 components)

Monitor and troubleshoot.

| Component | Purpose | When to Deploy | Cost |
|-----------|---------|----------------|------|
| monitoring | Metrics and alarms | Always (required) | $ |
| security-monitoring | Security scanning | Production | $$ |
| cost-monitoring | Cost tracking | Always (recommended) | Free |

**Category Guide**: [docs/library/observability/](./observability/README.md)

---

### Security (3 components)

Protect and secure.

| Component | Purpose | When to Deploy | Cost |
|-----------|---------|----------------|------|
| acm | SSL certificates | Custom domains | Free |
| idp-platform | Identity provider | SSO requirements | $ |
| cost-optimization | Cost reduction | Production | Negative |

**Category Guide**: [docs/library/security/](./security/README.md)

---

### Patterns (7 patterns)

Reference architectures.

| Pattern | Description | Components | Cost |
|---------|-------------|------------|------|
| three-tier-web-app | Classic web app | vpc, ecs, rds | $200-500 |
| microservices | Service-oriented | vpc, eks, rds | $1,000-2,000 |
| serverless-pipeline | Event-driven | lambda, apigateway | $50-200 |
| multi-region | Global deployment | All + replication | $2,000+ |
| production-ready | Full prod environment | All core components | $1,500-3,000 |
| minimal-deployment | Quick start | vpc, ecs, rds | $150-300 |
| development | Cost-optimized dev | vpc, ec2, rds | $100-200 |

**Category Guide**: [docs/library/patterns/](./patterns/README.md)

---

## Search by Cost

### Free Components

| Component | AWS Charges | Notes |
|-----------|-------------|-------|
| iam | $0 | IAM has no cost |
| securitygroup | $0 | Security groups are free |
| acm | $0 | Public SSL certificates are free |

### Low Cost ($ - Under $50/month)

| Component | Typical Cost | Cost Factors |
|-----------|--------------|--------------|
| backend | $5-20 | S3 storage, DynamoDB requests |
| secretsmanager | $5-20 | $0.40 per secret + API calls |
| lambda | $10-50 | Requests and compute time |
| dns | $1-10 | $0.50 per hosted zone + queries |
| monitoring | $10-30 | Dashboards, alarms, log storage |
| cost-monitoring | $0-10 | Minimal CloudWatch costs |
| eks-backend-services | $10-30 | Supporting services only |

### Medium Cost ($$ - $50-500/month)

| Component | Typical Cost | Cost Factors |
|-----------|--------------|--------------|
| vpc | $35-135 | NAT gateways ($32/month each) |
| ecs | $60-400 | Fargate: $30/vCPU, EC2: instance cost |
| ec2 | $60-500 | Instance type and count |
| apigateway | $50-200 | $3.50 per million requests |
| backup | $10-100 | Storage and restore operations |
| security-monitoring | $50-200 | GuardDuty, Config, Security Hub |
| eks-addons | $50-150 | ALB, EBS volumes, compute overhead |
| idp-platform | $50-200 | Cognito users and operations |

### High Cost ($$$ - Over $500/month)

| Component | Typical Cost | Cost Factors |
|-----------|--------------|--------------|
| eks | $300-2,000+ | $73 control plane + nodes |
| rds | $50-1,000+ | Instance class, storage, multi-AZ |
| cost-optimization | Negative | Reduces overall costs |

---

## Search by Complexity

### Low Complexity

**Quick to deploy, minimal configuration:**

| Component | Setup Time | Learning Curve |
|-----------|------------|----------------|
| backend | 10 min | Low |
| secretsmanager | 10 min | Low |
| iam | 15 min | Medium |
| securitygroup | 10 min | Low |
| lambda | 20 min | Low |
| acm | 15 min | Low |
| dns | 10 min | Low |

### Medium Complexity

**Moderate setup, some AWS knowledge needed:**

| Component | Setup Time | Learning Curve |
|-----------|------------|----------------|
| vpc | 30 min | Medium |
| ecs | 45 min | Medium |
| ec2 | 30 min | Low-Medium |
| rds | 45 min | Medium |
| apigateway | 30 min | Medium |
| monitoring | 30 min | Medium |
| backup | 30 min | Medium |

### High Complexity

**Extensive setup, deep expertise required:**

| Component | Setup Time | Learning Curve |
|-----------|------------|----------------|
| eks | 1-2 hours | High |
| eks-addons | 1 hour | High |
| security-monitoring | 1-2 hours | High |

---

## Search by Maturity

### Production Ready (✅)

All components are production-ready and battle-tested:

- backend, vpc, iam, securitygroup
- eks, eks-addons, eks-backend-services, ecs, ec2, lambda
- rds, secretsmanager, backup
- apigateway, external-secrets, dns
- monitoring, security-monitoring
- acm, idp-platform, cost-optimization

### Beta (🔵)

Currently, no components are in beta. All are production-ready.

### Alpha (🟡)

Currently, no components are in alpha. All are production-ready.

---

## Search by Tags

### Tag: networking

- vpc
- securitygroup
- dns

### Tag: compute

- eks
- eks-addons
- ecs
- ec2
- lambda

### Tag: storage

- rds
- secretsmanager
- backend

### Tag: security

- iam
- securitygroup
- acm
- secretsmanager
- security-monitoring

### Tag: serverless

- lambda
- apigateway
- ecs (Fargate)
- rds (Aurora Serverless)

### Tag: containers

- eks
- eks-addons
- ecs

### Tag: monitoring

- monitoring
- security-monitoring
- cost-monitoring

### Tag: high-availability

- vpc (multi-AZ NAT)
- eks (multi-AZ nodes)
- rds (multi-AZ)
- ecs (multi-AZ)

---

## Search by Environment Type

### Development

**Goal**: Minimize cost, maximize flexibility

| Component | Configuration | Cost |
|-----------|---------------|------|
| vpc | Single NAT | $35 |
| ecs | Fargate, 2 tasks | $60 |
| rds | db.t3.micro, single-AZ | $15 |
| monitoring | Basic alarms | $10 |
| **Total** | | **~$120/month** |

### Staging

**Goal**: Balance cost and production-like environment

| Component | Configuration | Cost |
|-----------|---------------|------|
| vpc | Single NAT | $35 |
| ecs | Fargate, 5 tasks | $150 |
| rds | db.t3.small, multi-AZ | $60 |
| monitoring | Enhanced monitoring | $20 |
| backup | Daily backups | $20 |
| **Total** | | **~$285/month** |

### Production

**Goal**: High availability, performance, security

| Component | Configuration | Cost |
|-----------|---------------|------|
| vpc | Multi-AZ NATs | $105 |
| eks | Cluster + 5 nodes | $500 |
| eks-addons | Full suite | $100 |
| rds | Aurora, multi-AZ | $300 |
| monitoring | Full observability | $50 |
| backup | Automated backups | $50 |
| security-monitoring | All services | $150 |
| **Total** | | **~$1,255/month** |

---

## Search by Deployment Dependency

### No Dependencies

Deploy these first:

- backend (first - enables collaboration)

### Tier 1 Dependencies

Deploy after backend:

- vpc
- iam

### Tier 2 Dependencies

Deploy after vpc/iam:

- securitygroup (requires: vpc)
- secretsmanager (no dependencies)
- acm (no dependencies)
- dns (no dependencies)

### Tier 3 Dependencies

Deploy after Tier 2:

- eks (requires: vpc, iam, securitygroup)
- ecs (requires: vpc, iam, securitygroup)
- ec2 (requires: vpc, iam, securitygroup)
- lambda (requires: iam, optional: vpc)
- rds (requires: vpc, securitygroup)

### Tier 4 Dependencies

Deploy after Tier 3:

- eks-addons (requires: eks)
- apigateway (requires: lambda or vpc)
- monitoring (requires: resources to monitor)

### Tier 5 Dependencies

Deploy last:

- backup (requires: resources to backup)
- security-monitoring (requires: resources to monitor)

---

## Search by Compliance Requirement

### HIPAA Compliance

**Required Components**:
- vpc (network isolation)
- securitygroup (access control)
- iam (least privilege)
- rds (encryption at rest/transit)
- secretsmanager (secure credentials)
- monitoring (audit logging)
- backup (data protection)
- security-monitoring (compliance validation)

### PCI-DSS Compliance

**Required Components**:
- vpc (network segmentation)
- securitygroup (firewall rules)
- iam (access control)
- acm (encryption in transit)
- monitoring (logging and monitoring)
- security-monitoring (vulnerability scanning)

### SOC 2 Compliance

**Required Components**:
- iam (access control)
- monitoring (change tracking)
- backup (availability)
- security-monitoring (continuous monitoring)

---

## Natural Language Search

### Question-Based Search

**Q: "How do I run a Node.js application?"**
A: Use **ecs** (ECS Fargate) for simple deployment or **eks** for complex orchestration. Add **apigateway** if exposing APIs.

**Q: "What's the cheapest way to run a cron job?"**
A: Use **lambda** with EventBridge schedule. Cost: ~$1-5/month.

**Q: "I need a highly available database"**
A: Use **rds** with `multi_az: true` and `engine: aurora-postgresql`. Cost: ~$300-500/month.

**Q: "How do I secure my infrastructure?"**
A: Start with **vpc** (private subnets), **iam** (least privilege), **securitygroup** (restrictive rules), **acm** (TLS), and **security-monitoring** (threat detection).

**Q: "What do I need for a production Kubernetes cluster?"**
A: **eks** + **eks-addons** + **rds** + **monitoring** + **backup**. Cost: ~$1,000-2,000/month.

**Q: "How can I reduce costs?"**
A: Use **cost-optimization** component, enable auto-scaling, use spot instances, implement auto-shutdown for dev/test.

---

## Advanced Search Filters

### Multi-Criteria Search

**Example: "Low-cost, serverless, production-ready API"**

Matches:
- **lambda** (serverless, low-cost, production)
- **apigateway** (API management, production)
- **secretsmanager** (secure storage, low-cost)
- **monitoring** (observability, low-cost)

Total Cost: ~$50-100/month

---

**Example: "High-availability, containerized microservices"**

Matches:
- **vpc** (multi-AZ networking)
- **eks** (Kubernetes orchestration)
- **eks-addons** (production capabilities)
- **rds** (multi-AZ database)
- **monitoring** (full observability)
- **backup** (data protection)

Total Cost: ~$1,500-2,500/month

---

## Quick Links

- **[Library Guide](../LIBRARY_GUIDE.md)** - Complete overview
- **[API Reference](./API_REFERENCE.md)** - Detailed component specs
- **[Category Guides](./README.md)** - Category documentation
- **[Examples](../../examples/)** - Working examples

---

## Tips for Effective Searching

1. **Start with use case** - "I need to..." is a great starting point
2. **Consider your budget** - Filter by cost range
3. **Match complexity to expertise** - Start simple, grow complex
4. **Check dependencies** - Deploy in the right order
5. **Review examples** - Learn from working implementations
6. **Read category guides** - Understand component relationships

---

**Last Updated**: 2025-12-02
**Total Components**: 24
**Total Patterns**: 7
**Search Methods**: 12
