# Route53 DNS Management in Atmos
> *Enterprise-grade DNS infrastructure for multi-account AWS environments*

## Table of Contents

- [Introduction](#introduction)
- [Architecture Patterns](#architecture-patterns)
- [Component Capabilities](#component-capabilities)
- [Implementation Guide](#implementation-guide)
- [Integration Examples](#integration-examples)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)
- [Appendix: Reference](#appendix-reference)

## Introduction

The Route53 DNS component for Atmos provides a production-ready solution for managing DNS infrastructure across AWS environments. It supports complex enterprise requirements including multi-account architectures, advanced routing configurations, and comprehensive health checks.

**Key Benefits:**
- **Complete DNS Management** - Unified control of public and private zones
- **Flexible Deployment Models** - Support for centralized, distributed, or hybrid architectures
- **Enhanced Resilience** - Built-in health checking and failover capabilities
- **Security-Focused** - Query logging, strict IAM controls, and DNSSEC support
- **Advanced Routing** - Weighted, latency, geolocation, and failover routing patterns

## Architecture Patterns

### Centralized DNS Architecture
![Centralized DNS Architecture](https://docs.aws.amazon.com/images/whitepapers/latest/building-scalable-secure-multi-vpc-network-infrastructure/images/image15.png)

In this model, DNS is managed in a dedicated shared services account:

```yaml
# Centralized DNS configuration
dns:
  multi_account_dns_delegation: true
  dns_account_assume_role_arn: "arn:aws:iam::${management_account_id}:role/DNSManagementRole"
  root_domain: "${tenant}.com"
  create_root_zone: true
```

**Recommended for:** Organizations requiring strict governance, consistent domain management, or regulatory compliance across environments.

**Advantages:**
- Centralized control and auditing
- Simplified DNS governance
- Consolidated DNS expertise
- Consistent domain structure

### Distributed DNS Architecture

With this pattern, each account manages its own independent DNS zones:

```yaml
# Distributed DNS configuration
dns:
  multi_account_dns_delegation: false
  root_domain: "${environment}.${tenant}.com"
  create_root_zone: true
```

**Recommended for:** Organizations with autonomous teams or environments that require complete separation.

**Advantages:**
- Simplified permissions model
- Environment isolation
- Independent DNS management
- Faster change implementation

### Hybrid DNS Architecture

The hybrid model balances centralization and autonomy, typically separating public and private DNS:

```yaml
# Hybrid DNS configuration 
dns:
  # Public DNS delegated to central account
  multi_account_dns_delegation: true
  dns_account_assume_role_arn: "arn:aws:iam::${management_account_id}:role/DNSManagementRole"
  root_domain: "${tenant}.com"
  
  # Private DNS managed locally
  zones:
    internal:
      name: "internal.${environment}.${tenant}.local"
      private_zone: true
      vpc_associations: ["${output.vpc.vpc_id}"]
```

**Recommended for:** Most enterprise environments seeking balance between governance and autonomy.

## Component Capabilities

### Zone Management
- **Public and Private Hosted Zones** - Support for internet-facing and internal DNS
- **Cross-Account Associations** - Link zones across AWS accounts
- **VPC Associations** - Connect private zones with multiple VPCs
- **Subdomain Delegation** - Create hierarchical zone structures

### Record Management
| Record Type | Use Case | Example |
|------------|----------|---------|
| **A/AAAA** | Direct IPv4/IPv6 address mapping | `api.example.com → 10.0.0.1` |
| **CNAME** | Domain aliases | `www.example.com → example.com` |
| **MX** | Mail server records | `example.com → mail.example.com` |
| **TXT** | Verification records, SPF | `example.com → "v=spf1 include:_spf.example.com ~all"` |
| **SRV** | Service discovery | `_service._proto.example.com → priority weight port target` |
| **CAA** | Certificate authority restrictions | `example.com → 0 issue "letsencrypt.org"` |
| **Aliases** | AWS service integration | `cdn.example.com → d1234.cloudfront.net` |

### Advanced Routing Capabilities
- **Weighted Routing** - Route traffic in specified proportions (A/B testing, blue/green deployment)
- **Latency-Based Routing** - Direct users to the lowest-latency endpoint
- **Geolocation Routing** - Route traffic based on user geographic location
- **Geoproximity Routing** - Route based on geographic proximity to resources
- **Failover Routing** - Automatic routing to backup resources
- **Multi-Value Answer** - Return multiple values for DNS queries

### Health Checking
- **Protocol Support** - HTTP, HTTPS, TCP health checks
- **String Matching** - Verify response content
- **Multiple Regions** - Distributed health checking from global locations
- **Threshold Settings** - Configurable failure thresholds
- **CloudWatch Integration** - Metrics and alerting

### Security Features
- **Query Logging** - Record all DNS queries to CloudWatch
- **IAM Role Integration** - Fine-grained access control
- **DNSSEC Support** - Cryptographic authentication of DNS records
- **Private DNS** - Internal-only DNS zones

## Implementation Guide

### Component Structure
The Route53 component follows Atmos best practices with clear separation of concerns:

```
components/terraform/dns/
├── main.tf           # Core DNS resources
├── variables.tf      # Input configuration
├── outputs.tf        # Exposed values
└── provider.tf       # AWS provider setup
```

### Configuration Workflow

1. **Define Root DNS Strategy**
   - Determine whether to use centralized, distributed, or hybrid architecture
   - Identify root domain and subdomain hierarchy

2. **Configure Zones and Records**
   - Set up hosted zones, delegation sets, and record structures
   - Define health checks for critical endpoints

3. **Implement Security Controls**
   - Configure query logging and IAM permissions
   - Set up cross-account access if needed

4. **Integrate with Other Components**
   - Connect DNS with load balancers, CDN, SSL certificates, etc.

### Sample Configuration

```yaml
# In catalog/network.yaml
dns:
  metadata:
    component: dns
  vars:
    enabled: true
    region: ${region}
    root_domain: "${tenant}.com"
    create_root_zone: false
    multi_account_dns_delegation: false
    
    # Zone configurations
    zones:
      main:
        name: "${environment}.${tenant}.com"
        comment: "Main zone for ${environment} environment"
        force_destroy: false
        enable_query_logging: true
      internal:
        name: "internal.${environment}.${tenant}.com"
        comment: "Internal DNS for ${environment} environment"
        vpc_associations: ["${output.vpc.vpc_id}"]
        force_destroy: false
```

### Environment-Specific Configuration

```yaml
# In account/dev/testenv-01/network.yaml
dns_zones:
  main:
    name: "testenv-01.example.com"
    enable_query_logging: true
    force_destroy: true  # Allow zone deletion in dev
  internal:
    name: "internal.testenv-01.example.com"
    vpc_associations: ["${output.vpc.vpc_id}"]
    
dns_records:
  app_endpoint:
    zone_name: "main"
    name: "app.testenv-01.example.com"
    type: "A"
    alias:
      name: "${output.alb.dns_name}"
      zone_id: "${output.alb.zone_id}"
```

## Integration Examples

### SSL Certificate Validation (ACM)

```yaml
# Certificate validation records for ACM
dns_records:
  acm_validation:
    zone_name: "main"
    name: "_12345.acm-validations.aws."
    type: "CNAME"
    ttl: 300
    records: ["_abcdef.acm-validations.aws."]
```

### Load Balancer Endpoints (ALB/NLB)

```yaml
# Application Load Balancer alias
dns_records:
  api_endpoint:
    zone_name: "main"
    name: "api.${environment}.${tenant}.com"
    type: "A"
    alias:
      name: "${output.alb.dns_name}"
      zone_id: "${output.alb.zone_id}"
      evaluate_target_health: true
```

### Content Delivery (CloudFront)

```yaml
# CloudFront distribution alias with health checks
dns_records:
  cdn_endpoint:
    zone_name: "main"
    name: "cdn.${environment}.${tenant}.com"
    type: "A"
    alias:
      name: "${output.cloudfront.domain_name}"
      zone_id: "${output.cloudfront.hosted_zone_id}"
      evaluate_target_health: true
    health_check_id: "cdn_health"

dns_health_checks:
  cdn_health:
    name: "cdn-health-check"
    fqdn: "cdn.${environment}.${tenant}.com"
    port: 443
    type: "HTTPS"
    resource_path: "/health"
    request_interval: 30
    failure_threshold: 3
```

### Kubernetes Service Discovery (EKS)

```yaml
# External-DNS integration for Kubernetes
dns_zones:
  k8s_services:
    name: "svc.${environment}.${tenant}.com"
    comment: "Zone for Kubernetes services"

# IAM role for ExternalDNS
iam_roles:
  external_dns:
    name: "${environment}-external-dns"
    policy_arns:
      - "${output.dns.zone_update_policy_arn}"
```

## Best Practices

### Security

| Best Practice | Implementation |
|--------------|----------------|
| **Implement Least Privilege** | Create specific IAM roles for DNS management |
| **Use Query Logging** | Enable `enable_query_logging: true` on all production zones |
| **Protect Sensitive Records** | Use private zones for internal services |
| **DNSSEC for Critical Domains** | Set `dnssec_enabled: true` for production domains |
| **Review Zone Permissions** | Regular audit of cross-account access |

### Operational Excellence

| Best Practice | Implementation |
|--------------|----------------|
| **Standardize TTL Strategy** | 300s standard / 60s migration / 3600s stable records |
| **Implement Health Checks** | Configure health checks for all critical endpoints |
| **Document DNS Architecture** | Maintain visualization of DNS hierarchy |
| **Failover Planning** | Configure failover routing for critical services |
| **Regional Resilience** | Multi-region health checks with regional routing |

### Cost Optimization

| Best Practice | Implementation |
|--------------|----------------|
| **Monitor Zone Count** | Set budget alerts for hosted zone count |
| **Clean Unused Records** | Regular review and cleanup of DNS records |
| **Right-size Health Checks** | Balance frequency and coverage of health checks |
| **Query Volume Analysis** | Monitor and optimize high-volume domains |

## Troubleshooting

### Common Issues and Solutions

| Issue | Possible Cause | Solution |
|-------|---------------|----------|
| **DNS resolution failure** | TTL caching, record misconfiguration | Check record in Route53 console, use `dig +trace` to follow resolution |
| **Health check failures** | Endpoint issue, firewall blocking | Verify endpoint directly, check security group rules |
| **Cross-account access denied** | IAM policy incorrect | Verify role trust relationship and permissions |
| **Record creation failing** | Duplicate record, validation error | Check for existing record with same name/type, verify YAML syntax |
| **Slow propagation** | High TTL, resolver caching | Reduce TTL before changes, verify with different resolvers |

### Diagnostic Tools

- **dig/nslookup** - Direct DNS querying
- **AWS CLI** - `aws route53 list-resource-record-sets`
- **AWS Console** - Route53 Health Check Status Dashboard
- **CloudWatch** - DNS query logs and metrics

## Appendix: Reference

### Variable Reference

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `root_domain` | string | Primary DNS domain | (required) |
| `create_root_zone` | bool | Whether to create the root domain zone | false |
| `multi_account_dns_delegation` | bool | Enable cross-account delegation | false |
| `dns_account_assume_role_arn` | string | Role ARN for DNS account | null |
| `zones` | map(object) | Map of zones to create | {} |
| `records` | map(object) | Map of DNS records | {} |
| `health_checks` | map(object) | Map of health checks | {} |

### Integration Matrix

| AWS Service | Integration Type | Notes |
|-------------|------------------|-------|
| **ACM** | CNAME validation records | Required for certificate issuance |
| **ALB/NLB** | Alias records | automatic health checking |
| **CloudFront** | Alias records | Global CDN endpoints |
| **S3 (website)** | Alias records | Static website hosting |
| **API Gateway** | Alias records | Regional/edge optimized APIs |
| **WorkMail** | MX/TXT records | Email service setup |
| **SES** | TXT/CNAME records | Email sending verification |
| **Cognito** | A records | Custom domains for auth |

### Further Reading

1. [AWS Route 53 Developer Guide](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/Welcome.html)
2. [DNS Management in Multi-Account Environments](https://aws.amazon.com/blogs/security/simplify-dns-management-in-a-multiaccount-environment-with-route-53-resolver/)
3. [Hybrid Cloud DNS Options](https://docs.aws.amazon.com/whitepapers/latest/hybrid-cloud-dns-options-for-vpc/scaling-dns-management-across-multiple-accounts-and-vpcs.html)
4. [Amazon Route 53 Application Recovery Controller](https://aws.amazon.com/route53/application-recovery-controller/)
