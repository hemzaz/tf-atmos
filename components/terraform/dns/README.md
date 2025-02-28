# DNS Component

_Last Updated: February 28, 2025_

## Overview

This component manages Route 53 hosted zones and DNS records for your AWS infrastructure, supporting both public and private zones, various record types, health checks, and advanced routing policies.

The DNS component provides a comprehensive solution for managing your AWS Route 53 resources, including hosted zones, records, health checks, traffic policies, and VPC associations. It supports multi-account setups with DNS delegation, query logging, and various routing strategies.

## Architecture

```
┌───────────────────────────────────────────────────────────┐
│                      DNS Component                         │
└───────────────────────────┬───────────────────────────────┘
                            │
                            ▼
┌───────────────────────────────────────────────────────────┐
│                                                           │
│               Route 53 / DNS Resources                     │
│                                                           │
│  ┌─────────────────┐     ┌───────────────────┐            │
│  │                 │     │                   │            │
│  │  Hosted Zones   │────►│    DNS Records    │            │
│  │                 │     │                   │            │
│  └─────────────────┘     └───────────────────┘            │
│         │   │                     ▲                       │
│         │   │                     │                       │
│         │   │                     │                       │
│  ┌──────▼───┴──────┐     ┌───────┴───────────┐           │
│  │                 │     │                   │           │
│  │  Private Zones  │     │   Health Checks   │           │
│  │                 │     │                   │           │
│  └─────────────────┘     └───────────────────┘           │
│         │                           │                     │
│         ▼                           │                     │
│  ┌─────────────────┐                │                     │
│  │                 │                │                     │
│  │  VPC            │                │                     │
│  │  Associations   │                │                     │
│  └─────────────────┘                │                     │
│                                     ▼                     │
│                          ┌────────────────────┐          │
│                          │                    │          │
│                          │  Routing Policies  │          │
│                          │  - Weighted        │          │
│                          │  - Latency         │          │
│                          │  - Failover        │          │
│                          │  - Geolocation     │          │
│                          └────────────────────┘          │
│                                                           │
└───────────────────────────────────────────────────────────┘
```

## Features

- Create and manage public and private Route 53 hosted zones
- Define DNS records with various types (A, AAAA, CNAME, MX, TXT, etc.)
- Support for alias records to AWS resources (ALB, CloudFront, S3, etc.)
- Advanced routing policies (weighted, latency-based, geolocation, failover)
- Route 53 health checks for endpoint monitoring
- DNS query logging to CloudWatch
- Multi-account DNS management with delegation
- Reusable delegation sets
- Traffic policies for complex routing scenarios
- VPC associations for private hosted zones
- Cross-account DNS resolution

## Usage

### Basic Usage

```yaml
components:
  terraform:
    dns:
      vars:
        region: us-west-2
        root_domain: example.com
        
        # Create a public hosted zone
        zones:
          "example.com":
            name: "example.com"
            comment: "Public hosted zone for example.com"
            force_destroy: false
            vpc_associations: []
            tags:
              Environment: "production"
        
        # Define DNS records
        records:
          "www-a":
            zone_name: "example.com"
            name: "www"
            type: "A"
            ttl: 300
            records: ["203.0.113.1"]
          
          "mail-mx":
            zone_name: "example.com"
            name: ""
            type: "MX"
            ttl: 3600
            records: ["10 mail.example.com"]
```

### Advanced Configuration

```yaml
components:
  terraform:
    dns:
      vars:
        region: us-west-2
        root_domain: example.com
        multi_account_dns_delegation: true
        dns_account_assume_role_arn: "arn:aws:iam::111122223333:role/DNSAdmin"
        
        # Delegation sets for consistent name servers
        delegation_sets:
          "primary":
            name: "primary-delegation-set"
            reference_name: "primary-nameservers"
            
        # Public and private hosted zones
        zones:
          "example.com":
            name: "example.com"
            comment: "Public zone with query logging"
            force_destroy: false
            enable_query_logging: true
            query_logging_config:
              retention_days: 90
              
          "internal.example.com":
            name: "internal.example.com"
            comment: "Private zone for internal services"
            force_destroy: false
            vpc_associations: ["${dep.vpc.outputs.vpc_id}"]
        
        # Health checks for endpoints
        health_checks:
          "api-health":
            name: "api-healthcheck"
            fqdn: "api.example.com"
            port: 443
            type: "HTTPS"
            resource_path: "/health"
            failure_threshold: 3
            request_interval: 30
            regions: ["us-west-1", "us-east-1", "eu-west-1"]
        
        # Various record types including advanced routing
        records:
          "api-a":
            zone_name: "example.com"
            name: "api"
            type: "A"
            alias:
              name: "${dep.apigateway.outputs.alb_dns_name}"
              zone_id: "${dep.apigateway.outputs.alb_zone_id}"
              evaluate_target_health: true
          
          "cdn-a":
            zone_name: "example.com"
            name: "cdn"
            type: "A"
            alias:
              name: "${dep.cloudfront.outputs.distribution_domain_name}"
              zone_id: "Z2FDTNDATAQYW2"  # CloudFront zone ID
              evaluate_target_health: false
              
          "app-failover":
            zone_name: "example.com"
            name: "app"
            type: "A"
            set_identifier: "primary"
            records: ["192.168.1.1"]
            failover_routing_policy:
              type: "PRIMARY"
            health_check_id: "api-health"
            
          "app-failover-secondary":
            zone_name: "example.com"
            name: "app" 
            type: "A"
            set_identifier: "secondary"
            records: ["192.168.2.1"]
            failover_routing_policy:
              type: "SECONDARY"
              
        # VPC associations for cross-account DNS resolution
        vpc_dns_resolution:
          "shared-services-vpc":
            vpc_id: "${dep.vpc.outputs.vpc_id}"
            associated_zones: ["internal.example.com"]
```

## Input Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `region` | AWS region | `string` | n/a | Yes |
| `assume_role_arn` | ARN of the IAM role to assume for the main account | `string` | `null` | No |
| `dns_account_assume_role_arn` | ARN of the IAM role to assume in the DNS account (if using multi-account setup) | `string` | `null` | No |
| `root_domain` | The root domain name (e.g., example.com) | `string` | n/a | Yes |
| `create_root_zone` | Whether to create the root zone (set to false if the zone already exists) | `bool` | `false` | No |
| `multi_account_dns_delegation` | Whether to create delegations across accounts (true if DNS managed in a separate account) | `bool` | `false` | No |
| `zones` | Map of Route53 zones to create | `map(object)` | `{}` | No |
| `records` | Map of Route53 records to create | `map(object)` | `{}` | No |
| `health_checks` | Map of Route53 health checks to create | `map(object)` | `{}` | No |
| `delegation_sets` | Map of reusable delegation sets | `map(object)` | `{}` | No |
| `traffic_policies` | Map of Route53 traffic policies | `map(object)` | `{}` | No |
| `vpc_dns_resolution` | Map of VPC associations for private hosted zones | `map(object)` | `{}` | No |
| `tags` | Common tags to apply to all resources | `map(string)` | `{}` | No |

### Zone Object Structure

```yaml
zones:
  "zone-key":
    name: string                    # Domain name for the zone
    comment: string                 # Description of the zone
    force_destroy: bool             # Whether to force deletion of records when zone is destroyed
    delegation_set_id: string       # Optional ID of a reusable delegation set
    enable_health_checks: bool      # Whether to enable health checks for the zone
    default_ttl: number            # Default TTL for records in the zone
    enable_query_logging: bool      # Whether to enable query logging
    query_logging_config: map       # Configuration for query logging
    vpc_associations: list(string)  # List of VPC IDs to associate with a private zone
    tags: map(string)               # Tags to apply to the zone
```

### Record Object Structure

```yaml
records:
  "record-key":
    zone_name: string               # Name of the zone to add the record to
    name: string                    # Record name (without the zone name)
    type: string                    # Record type (A, AAAA, CNAME, MX, TXT, etc.)
    ttl: number                    # Time to live for the record
    records: list(string)          # Record values
    alias: map                     # Configuration for alias records
    health_check_id: string        # ID of a health check to associate
    set_identifier: string         # Unique identifier for the record when using routing policies
    weighted_routing_policy: map   # Configuration for weighted routing
    latency_routing_policy: map    # Configuration for latency-based routing
    geolocation_routing_policy: map # Configuration for geolocation routing
    failover_routing_policy: map   # Configuration for failover routing
    multivalue_answer_routing_policy: bool # Whether to enable multivalue answer routing
```

### Health Check Object Structure

```yaml
health_checks:
  "health-check-key":
    name: string                   # Name of the health check
    fqdn: string                   # Fully qualified domain name to check
    ip_address: string             # IP address to check (alternative to FQDN)
    port: number                   # Port to check
    type: string                   # Check type (HTTP, HTTPS, TCP, etc.)
    resource_path: string          # Path to check for HTTP(S) checks
    search_string: string          # String to search for in the response
    request_interval: number       # Interval between checks in seconds
    failure_threshold: number      # Number of consecutive failures to trigger failure
    measure_latency: bool          # Whether to measure latency
    invert_healthcheck: bool       # Whether to invert the result
    regions: list(string)          # Regions to check from
    tags: map(string)              # Tags to apply to the health check
```

## Outputs

| Name | Description |
|------|-------------|
| `zone_ids` | Map of zone names to their IDs |
| `zone_name_servers` | Map of zone names to their name servers |
| `delegation_set_name_servers` | Map of delegation set IDs to their name servers |
| `records` | Map of created record IDs to their attributes |
| `health_check_ids` | Map of health check names to their IDs |
| `traffic_policy_ids` | Map of traffic policy names to their IDs |
| `root_domain` | The root domain used for DNS configuration |
| `domain_validation_options` | Domain validation options for certificates if ACM is integrated |
| `private_zone_vpc_associations` | Map of private zone VPC associations |

## Examples

### Public Hosted Zone with Various Record Types

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    dns/public:
      vars:
        region: us-west-2
        root_domain: example.com
        
        # Hosted Zone
        zones:
          "example.com":
            name: "example.com"
            comment: "Public hosted zone for example.com"
            force_destroy: false
        
        # DNS Records
        records:
          "www-a":
            zone_name: "example.com"
            name: "www"
            type: "A"
            ttl: 300
            records: ["203.0.113.1"]
          
          "api-cname":
            zone_name: "example.com"
            name: "api"
            type: "CNAME"
            ttl: 300
            records: ["api-gateway.amazonaws.com"]
          
          "txt-spf":
            zone_name: "example.com"
            name: ""
            type: "TXT"
            ttl: 3600
            records: ["v=spf1 include:_spf.example.com ~all"]
          
          "mail-mx":
            zone_name: "example.com"
            name: ""
            type: "MX"
            ttl: 3600
            records: ["10 mail.example.com"]
```

### Private Hosted Zone for VPC

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    dns/private:
      vars:
        region: us-west-2
        root_domain: internal.example.com
        
        # Hosted Zone
        zones:
          "internal.example.com":
            name: "internal.example.com"
            comment: "Private hosted zone for internal resources"
            force_destroy: false
            vpc_associations: ["${dep.vpc.outputs.vpc_id}"]
        
        # DNS Records
        records:
          "db-a":
            zone_name: "internal.example.com"
            name: "db"
            type: "A"
            ttl: 300
            records: ["10.0.1.10"]
          
          "cache-a":
            zone_name: "internal.example.com"
            name: "cache"
            type: "A"
            ttl: 300
            records: ["10.0.2.20"]
```

### Failover Configuration with Health Checks

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    dns/failover:
      vars:
        region: us-west-2
        root_domain: example.com
        
        # Hosted Zone
        zones:
          "example.com":
            name: "example.com"
            comment: "Public hosted zone with failover configuration"
        
        # Health Checks
        health_checks:
          "primary-check":
            name: "primary-endpoint-check"
            fqdn: "primary.example.com"
            port: 443
            type: "HTTPS"
            resource_path: "/health"
            failure_threshold: 2
            request_interval: 10
        
        # Failover Records
        records:
          "app-primary":
            zone_name: "example.com"
            name: "app"
            type: "A"
            ttl: 60
            records: ["203.0.113.1"]
            set_identifier: "primary"
            failover_routing_policy:
              type: "PRIMARY"
            health_check_id: "primary-check"
          
          "app-secondary":
            zone_name: "example.com"
            name: "app"
            type: "A"
            ttl: 60
            records: ["203.0.113.2"]
            set_identifier: "secondary"
            failover_routing_policy:
              type: "SECONDARY"
```

### Multi-Region Latency-Based Routing

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    dns/latency:
      vars:
        region: us-west-2
        root_domain: example.com
        
        # Hosted Zone
        zones:
          "example.com":
            name: "example.com"
        
        # Latency-Based Records
        records:
          "api-us-west":
            zone_name: "example.com"
            name: "api"
            type: "A"
            ttl: 60
            records: ["203.0.113.1"]
            set_identifier: "us-west"
            latency_routing_policy:
              region: "us-west-2"
          
          "api-us-east":
            zone_name: "example.com"
            name: "api" 
            type: "A"
            ttl: 60
            records: ["203.0.113.2"]
            set_identifier: "us-east"
            latency_routing_policy:
              region: "us-east-1"
          
          "api-eu-west":
            zone_name: "example.com"
            name: "api"
            type: "A"
            ttl: 60
            records: ["203.0.113.3"]
            set_identifier: "eu-west"
            latency_routing_policy:
              region: "eu-west-1"
```

## Related Components

- [ACM](../acm/README.md) - For certificate validation using DNS records
- [APIGateway](../apigateway/README.md) - For creating DNS records pointing to API Gateway endpoints
- [ECS](../ecs/README.md) - For service discovery via Route 53
- [VPC](../vpc/README.md) - For private hosted zones associated with VPCs

## Best Practices

1. **Security**:
   - Use private hosted zones for internal resources
   - Restrict access to DNS management through IAM policies
   - Consider DNSSEC for critical domains
   - Apply least privilege principles for cross-account DNS management

2. **Reliability**:
   - Configure appropriate TTL values based on change frequency
   - Use health checks for critical endpoints
   - Implement failover configurations for high-availability services
   - Test failover scenarios regularly

3. **Organization**:
   - Use consistent naming conventions for DNS records
   - Tag resources appropriately for cost allocation and management
   - Document DNS architecture and delegations
   - Maintain a centralized DNS record inventory

4. **Cost Optimization**:
   - Monitor unused hosted zones and records
   - Be mindful of health check frequency for cost management
   - Use alias records for AWS resources to avoid charges for DNS queries
   - Clean up orphaned health checks and records

5. **Multi-Account Setup**:
   - Use a dedicated DNS account for centralized management of public zones
   - Implement proper cross-account role permissions
   - Use private zones in application accounts for internal resolution
   - Consider Route 53 Resolver for complex hybrid environments

## Troubleshooting

### Zone Creation Issues

If you encounter errors when creating hosted zones:

- Verify that you have the necessary IAM permissions (`route53:CreateHostedZone`)
- Check for duplicate zone names in your AWS account
- For private zones, ensure the VPC exists and you have permissions to associate it

### DNS Resolution Problems

If DNS records are not resolving as expected:

- Verify the record was created successfully with the correct values
- Check TTL values and allow time for DNS propagation (up to 48 hours for global propagation)
- For private zones, ensure the VPC is correctly associated and DNS resolution is enabled
- Use `dig` or `nslookup` tools to troubleshoot resolution issues

```bash
dig @8.8.8.8 example.com
dig @8.8.8.8 www.example.com
nslookup -type=MX example.com
```

### Health Check Failures

If health checks are failing unexpectedly:

- Verify the endpoint is accessible from the internet (for public health checks)
- Check firewall rules to ensure AWS health check IP ranges are allowed
- Inspect the health check threshold and interval settings
- Review CloudWatch metrics for the health check to identify patterns

### Cross-Account Access Issues

For multi-account DNS setups:

- Verify the assume role configurations are correct
- Check that trust relationships are properly configured in IAM roles
- Ensure the correct provider is specified for each resource
- Use AWS CloudTrail to debug permission-related errors

## Resources

- [AWS Route 53 Documentation](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/Welcome.html)
- [Terraform AWS Route 53 Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_zone)
- [DNS Best Practices in AWS](https://aws.amazon.com/blogs/networking-and-content-delivery/top-10-dns-route-53-questions/)
- [Route 53 FAQs](https://aws.amazon.com/route53/faqs/)