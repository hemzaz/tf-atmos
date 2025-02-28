# DNS Component

This component manages Route 53 hosted zones and DNS records for your AWS infrastructure.

## Features

- Create and manage public and private Route 53 hosted zones
- Define DNS records (A, AAAA, CNAME, MX, TXT, etc.)
- Configure DNS delegation
- Support for DNS failover configurations
- Route 53 health checks
- Alias records for AWS resources

## Usage

```hcl
module "dns" {
  source = "git::https://github.com/example/tf-atmos.git//components/terraform/dns"
  
  region = var.region
  
  # Hosted Zone Configuration
  hosted_zones = {
    "example.com" = {
      name          = "example.com"
      comment       = "Public hosted zone for example.com"
      force_destroy = false
      is_private    = false
      tags = {
        Environment = "production"
      }
    },
    "internal.example.com" = {
      name          = "internal.example.com"
      comment       = "Private hosted zone for internal resources"
      force_destroy = false
      is_private    = true
      vpc_id        = "vpc-12345678" # Optional for private zones
      tags = {
        Environment = "production"
      }
    }
  }
  
  # DNS Records Configuration
  records = {
    "www-a" = {
      zone_name = "example.com"
      name      = "www"
      type      = "A"
      ttl       = 300
      records   = ["10.0.0.1"]
    },
    "mail-mx" = {
      zone_name = "example.com"
      name      = ""
      type      = "MX"
      ttl       = 3600
      records   = ["10 mail.example.com"]
    },
    "app-alias" = {
      zone_name = "example.com"
      name      = "app"
      type      = "A"
      alias = {
        name                   = "lb-123456.us-west-2.elb.amazonaws.com"
        zone_id                = "Z3DZXE0Q79N41H" # Load balancer hosted zone ID
        evaluate_target_health = true
      }
    }
  }
  
  # Health Checks  
  health_checks = {
    "web-health" = {
      fqdn              = "www.example.com"
      port              = 443
      type              = "HTTPS"
      resource_path     = "/health"
      failure_threshold = 3
      request_interval  = 30
      tags = {
        Name = "www-health-check"
      }
    }
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| region | AWS region | `string` | n/a | yes |
| hosted_zones | Map of hosted zones to create | `map(any)` | `{}` | no |
| records | Map of DNS records to create | `map(any)` | `{}` | no |
| health_checks | Map of Route 53 health checks to create | `map(any)` | `{}` | no |
| delegation_sets | Map of reusable delegation sets | `map(any)` | `{}` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| hosted_zone_ids | Map of hosted zone names to their IDs |
| hosted_zone_name_servers | Map of hosted zone names to their name servers |
| health_check_ids | Map of health check names to their IDs |
| record_fqdns | Map of record names to their FQDNs |

## Examples

### Public Hosted Zone with Various Record Types

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    dns/public:
      vars:
        region: us-west-2
        
        # Hosted Zone
        hosted_zones:
          "example.com":
            name: "example.com"
            comment: "Public hosted zone for example.com"
            force_destroy: false
            is_private: false
        
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
        
        # Hosted Zone
        hosted_zones:
          "internal.example.com":
            name: "internal.example.com"
            comment: "Private hosted zone for internal resources"
            force_destroy: false
            is_private: true
            vpc_id: ${dep.vpc.outputs.vpc_id}
        
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

### Alias Records for AWS Resources

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    dns/aliases:
      vars:
        region: us-west-2
        
        # Hosted Zone
        hosted_zones:
          "example.com":
            name: "example.com"
            is_private: false
        
        # Alias Records
        records:
          "app-alb":
            zone_name: "example.com"
            name: "app"
            type: "A"
            alias:
              name: ${dep.apigateway.outputs.alb_dns_name}
              zone_id: ${dep.apigateway.outputs.alb_zone_id}
              evaluate_target_health: true
          
          "cdn-cf":
            zone_name: "example.com"
            name: "cdn"
            type: "A"
            alias:
              name: "d123456abcdef8.cloudfront.net"
              zone_id: "Z2FDTNDATAQYW2" # CloudFront zone ID
              evaluate_target_health: false
```

## Best Practices

1. **Security**:
   - Use private hosted zones for internal resources
   - Restrict access to DNS management through IAM policies
   - Consider DNSSEC for critical domains

2. **Reliability**:
   - Configure appropriate TTL values based on change frequency
   - Use health checks for critical endpoints
   - Implement failover configurations for high-availability

3. **Organization**:
   - Use consistent naming conventions for DNS records
   - Tag resources appropriately
   - Document DNS architecture and delegations

4. **Cost Optimization**:
   - Monitor unused hosted zones and records
   - Be mindful of health check frequency for cost management