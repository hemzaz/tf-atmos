# ACM (AWS Certificate Manager) Component

_Last Updated: February 28, 2025_

This component manages SSL/TLS certificates for domains using AWS Certificate Manager. It supports both DNS and email validation methods, with strong validation to prevent misconfigurations.

## Overview

This component creates and manages ACM certificates for your domains with the following features:

- Certificate creation for multiple domains with a single component
- Support for wildcard certificates and subject alternative names (SANs)
- DNS validation with automatic Route53 record creation
- Email validation option for domains not managed in Route53
- Extensive validation to prevent misconfigurations
- Certificate transparency logging control
- Secure certificate lifecycle management

## Architecture

The ACM component creates a certificate infrastructure that integrates with other AWS services:

```
                                     +--------------------+
                                     |                    |
                                     |  AWS Certificate   |
                                     |     Manager        |
                                     |                    |
                                     +--------+-----------+
                                              |
                                              | (Certificate validation)
                                              |
                      +----------------------+------------------------+
                      |                      |                        |
              +-------v--------+    +--------v-------+     +---------v--------+
              |                |    |                |     |                  |
              |  DNS           |    |  Email         |     |  Certificate     |
              |  Validation    |    |  Validation    |     |  Export          |
              |                |    |                |     |                  |
              +-------+--------+    +----------------+     +------------------+
                      |
                      | (creates records)
                      |
              +-------v--------+
              |                |
              |   Route53      |
              |   Zone         |
              |                |
              +----------------+

    Certificate Users:
    +----------------+    +----------------+    +----------------+    +---------------+
    |                |    |                |    |                |    |               |
    |  CloudFront    |    |  API Gateway   |    |  Application   |    |  EKS/Istio    |
    |  Distribution  |    |                |    |  Load Balancer |    |  Ingress      |
    |                |    |                |    |                |    |               |
    +----------------+    +----------------+    +----------------+    +---------------+
```

## Usage

### Basic Usage

```yaml
# catalog/acm.yaml
components:
  terraform:
    acm:
      vars:
        region: ${region}
        zone_id: "${output.dns.zones.main.zone_id}"
        
        dns_domains:
          main:
            domain_name: "example.com"
            subject_alternative_names: ["www.example.com", "api.example.com"]
            validation_method: "DNS"
            wait_for_validation: true
          
          wildcard:
            domain_name: "*.example.com"
            validation_method: "DNS"
        
        tags:
          Environment: "Development"
          Owner: "Platform Team"
```

### Environment-specific Configuration

```yaml
# account/dev/us-east-1/acm.yaml
import:
  - catalog/acm

vars:
  environment: us-east-1
  region: us-east-1
  tenant: mycompany
  
  # Override catalog settings
  dns_domains:
    main:
      domain_name: "dev.example.com"
      subject_alternative_names: ["api.dev.example.com"]
      validation_method: "DNS"
    
    api_wildcard:
      domain_name: "*.api.dev.example.com"
      validation_method: "DNS"

tags:
  Environment: "Development"
  Team: "Platform"
  CostCenter: "Platform-1234"
```

## Input Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `region` | AWS region | `string` | - | Yes |
| `zone_id` | Route53 zone ID to create validation records in | `string` | - | Yes |
| `dns_domains` | Map of domain configurations to create ACM certificates for | `map(object)` | `{}` | Yes |
| `cert_transparency_logging` | Whether to enable certificate transparency logging | `bool` | `true` | No |
| `tags` | Tags to apply to resources | `map(string)` | `{}` | Yes |

### dns_domains Object Structure

```yaml
dns_domains:
  key_name:
    domain_name: string                        # Required: Domain name for the certificate
    subject_alternative_names: list(string)    # Optional: List of alternative domain names
    validation_method: string                  # Optional: "DNS" or "EMAIL", defaults to "DNS"
    wait_for_validation: bool                  # Optional: Whether to wait for validation, defaults to true
    tags: map(string)                          # Optional: Additional tags for this certificate
```

## Outputs

| Name | Description |
|------|-------------|
| `certificate_arns` | Map of certificate keys to their ARNs |
| `certificate_domains` | Map of certificate keys to their domain names |
| `certificate_validation_ids` | Map of certificate keys to their validation IDs |
| `certificate_keys` | Placeholder for certificate private keys (requires export script) |
| `certificate_crts` | Placeholder for certificate public certs (requires export script) |
| `export_instructions` | Instructions for exporting certificates from ACM |

## Features

### Multiple Certificate Management

Create and manage multiple certificates in a single component:

```yaml
dns_domains:
  main_domain:
    domain_name: "example.com"
    subject_alternative_names: ["www.example.com"]
  
  api_domain:
    domain_name: "api.example.com"
  
  wildcard:
    domain_name: "*.example.com"
```

### Validation Methods

Choose between DNS or email validation:

```yaml
# DNS validation (recommended)
dns_domains:
  main:
    domain_name: "example.com"
    validation_method: "DNS"
    wait_for_validation: true

# Email validation
dns_domains:
  external:
    domain_name: "external-domain.com"
    validation_method: "EMAIL"
```

### Certificate Export

ACM does not allow direct private key export through the API. For services that need direct access to certificate files (like Istio in EKS), use the export script:

```bash
./scripts/certificates/export-cert.sh -a <CERTIFICATE_ARN> -r <REGION> -u
```

The `-u` flag will upload the certificate to AWS Secrets Manager, allowing integration with External Secrets Operator in Kubernetes.

## Examples

### Basic Website Certificate

```yaml
vars:
  zone_id: "${output.dns.zones.main.zone_id}"
  dns_domains:
    website:
      domain_name: "example.com"
      subject_alternative_names: ["www.example.com"]
      validation_method: "DNS"
      wait_for_validation: true
```

### Wildcard Certificate

```yaml
vars:
  zone_id: "${output.dns.zones.main.zone_id}"
  dns_domains:
    wildcard:
      domain_name: "*.example.com"
      validation_method: "DNS"
      wait_for_validation: true
```

### Multi-Domain Certificate for Microservices

```yaml
vars:
  zone_id: "${output.dns.zones.main.zone_id}"
  dns_domains:
    api_gateway:
      domain_name: "api.example.com"
      subject_alternative_names: [
        "auth.api.example.com",
        "users.api.example.com",
        "orders.api.example.com",
        "payments.api.example.com"
      ]
      validation_method: "DNS"
      wait_for_validation: true
```

## Related Components

- [**dns**](../dns/README.md) - For creating and managing Route53 zones needed for DNS validation
- [**eks-addons**](../eks-addons/README.md) - For using certificates with Istio ingress gateways
- [**apigateway**](../apigateway/README.md) - For configuring custom domains with API Gateway
- [**external-secrets**](../external-secrets/README.md) - For securely managing certificate files in Kubernetes

## Best Practices

- Always use DNS validation when possible, as it's more automated and reliable
- Create wildcard certificates for development environments to simplify management
- Use specific certificates for production workloads for better security isolation
- Enable certificate transparency logging for security compliance
- Plan for certificate renewal 30 days before expiration
- Store exported certificates in AWS Secrets Manager
- Use the External Secrets Operator pattern for Kubernetes workloads
- Add domain validation records to your infrastructure as code for consistency

## Troubleshooting

### Common Issues

1. **Validation Timeout**
   - DNS propagation can take time
   - Check that validation records were created properly

   ```bash
   # Verify DNS records exist in Route53
   aws route53 list-resource-record-sets --hosted-zone-id <ZONE_ID> | grep -A 3 "_acm-challenge"
   ```

2. **Email Validation Issues**
   - Ensure WHOIS privacy protection is disabled
   - Check all email addresses listed in the WHOIS record
   - Look for validation emails in spam folders

3. **Certificate Usage Failures**
   - Ensure the certificate and service are in the same region
   - Verify the certificate covers all required domains
   - Check for certificate status issues

   ```bash
   # Check certificate status
   aws acm describe-certificate --certificate-arn <CERTIFICATE_ARN> --region <REGION>
   ```

4. **Certificate Export Problems**
   - ACM does not allow API-based export of private keys
   - Use the provided export script
   - Ensure AWS CLI has the appropriate permissions

### Validation Commands

```bash
# Validate component configuration
atmos terraform validate acm -s mycompany-dev-us-east-1

# Check component outputs after deployment
atmos terraform output acm -s mycompany-dev-us-east-1

# List all certificates in a region
aws acm list-certificates --region <REGION>

# Describe a specific certificate
aws acm describe-certificate --certificate-arn <CERTIFICATE_ARN> --region <REGION>
```