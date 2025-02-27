# DNS Management in Atmos with Route53

## Overview

This documentation covers the implementation and best practices for DNS management in the Atmos framework using the Route53 component. The component is designed to be fully flexible and robust, supporting both centralized and distributed DNS management patterns.

## Architecture Options

The Route53 component supports three primary architectural patterns:

### 1. Centralized DNS Management

In this model, DNS is managed in a shared services account:

- Root domain and all subdomains managed in a central account
- Cross-account access roles for environment-specific management
- VPC associations across accounts via Resource Access Manager (RAM)
- Ideal for: Organizations with strict governance requirements

```yaml
# Example of centralized DNS in shared services account
dns:
  multi_account_dns_delegation: true
  dns_account_assume_role_arn: "arn:aws:iam::${management_account_id}:role/DNSManagementRole"
```

### 2. Distributed DNS Management

In this model, each environment manages its own DNS zones:

- Environment-specific zones in each account
- No cross-account delegation required
- Simpler but less centralized governance
- Ideal for: Organizations with autonomous teams

```yaml
# Example of distributed DNS in environment account
dns:
  multi_account_dns_delegation: false
  root_domain: "${tenant}.com"
  create_root_zone: false
```

### 3. Hybrid Model

This combines aspects of both approaches:

- Public DNS managed centrally (for consistent external presence)
- Private DNS managed in environment accounts (for internal resolution)
- Cross-account roles for public DNS updates
- Ideal for: Balance of governance and autonomy

## Component Features

The DNS component offers these key features:

1. **Flexible Zone Management**:
   - Public and private hosted zones
   - Root domains and subdomains
   - VPC associations for private zones
   - Cross-account zone associations

2. **Comprehensive Record Management**:
   - Support for all Route53 record types (A, AAAA, CNAME, MX, TXT, etc.)
   - Advanced routing policies (weighted, latency, failover, geolocation)
   - Alias records for AWS resources (ALBs, CloudFront, S3)

3. **Health Checking & Monitoring**:
   - HTTP/HTTPS health checks
   - TCP health checks
   - String matching checks
   - Regional health checking
   - CloudWatch integration

4. **Security Features**:
   - Query logging to CloudWatch
   - IAM role-based access control
   - Cross-account security boundaries
   - DNSSEC support (optional)

5. **Performance Optimization**:
   - Traffic flow management
   - Latency-based routing
   - Geolocation routing
   - Multi-value answers

## Implementation with Atmos

### Component Structure

The component follows Atmos best practices with clear separation of concerns:

- `variables.tf`: Defines all configuration options
- `main.tf`: Implements core functionality
- `outputs.tf`: Exposes important values for cross-component references
- `provider.tf`: Handles AWS provider configuration including cross-account access

### Stack Configuration

DNS is configured through the network stack:

```yaml
# In catalog/network.yaml
dns:
  metadata:
    component: dns
  vars:
    root_domain: "${tenant}.com"
    zones:
      main:
        name: "${environment}.${tenant}.com"
      internal:
        name: "internal.${environment}.${tenant}.com"
        vpc_associations: ["${output.vpc.vpc_id}"]
```

### Environment Overrides

Environment-specific settings are defined in environment stack files:

```yaml
# In account/dev/env-01/network.yaml
dns_zones:
  main:
    name: "dev-01.example.com"
    enable_query_logging: true
  internal:
    name: "internal.dev-01.example.com"
    vpc_associations: ["vpc-12345"]
```

## Integration with Other Components

### With ACM Component

```yaml
# Example record using ACM certificate validation
dns_records:
  cert_validation:
    zone_name: "main"
    name: "_abcdef.example.com"
    type: "CNAME"
    records: ["_validation.acm-validations.aws."]
```

### With ALB/ELB Components

```yaml
# Example ALB alias record
dns_records:
  app_endpoint:
    zone_name: "main"
    name: "app.example.com"
    type: "A"
    alias:
      name: "${output.alb.dns_name}"
      zone_id: "${output.alb.zone_id}"
```

### With CloudFront Component

```yaml
# Example CloudFront distribution alias
dns_records:
  cdn_endpoint:
    zone_name: "main"
    name: "cdn.example.com"
    type: "A"
    alias:
      name: "${output.cloudfront.domain_name}"
      zone_id: "${output.cloudfront.hosted_zone_id}"
```

## Security Best Practices

1. **IAM Permissions**:
   - Use least privilege principle
   - Separate roles for development and production zones
   - Conditional IAM policies for extra protection

2. **DNS Query Logging**:
   - Enable query logging in production environments
   - Set appropriate log retention periods
   - Implement log analysis for anomaly detection

3. **Access Control**:
   - Multi-account strategy for isolation
   - Service control policies to prevent unauthorized zone creation
   - Restricted access to production DNS zones

4. **Data Protection**:
   - Consider enabling DNSSEC for critical domains
   - Private zones for internal services
   - No sensitive information in DNS records

## Operational Considerations

1. **TTL Settings**:
   - Lower TTLs for frequently changing records (60-300 seconds)
   - Higher TTLs for stable records (3600+ seconds)
   - Special considerations during migrations (gradual TTL reduction)

2. **Health Checks**:
   - Monitor critical endpoints
   - Implement multi-region checks for global services
   - Set appropriate thresholds and intervals

3. **Disaster Recovery**:
   - Configure failover routing for critical services
   - Document DNS recovery procedures
   - Consider Route53 Application Recovery Controller for critical workloads

4. **Cost Management**:
   - Monitor hosted zone and health check counts
   - Clean up unused zones and records
   - Consider query volume for high-traffic domains

## Sources and References

1. [AWS Route 53 Developer Guide](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/Welcome.html)
2. [DNS Management in Multi-Account Environments](https://aws.amazon.com/blogs/security/simplify-dns-management-in-a-multiaccount-environment-with-route-53-resolver/)
3. [Hybrid Cloud DNS Options](https://docs.aws.amazon.com/whitepapers/latest/hybrid-cloud-dns-options-for-vpc/scaling-dns-management-across-multiple-accounts-and-vpcs.html)
4. [Centralized DNS Management](https://aws.amazon.com/blogs/networking-and-content-delivery/centralized-dns-management-of-hybrid-cloud-with-amazon-route-53-and-aws-transit-gateway/)
