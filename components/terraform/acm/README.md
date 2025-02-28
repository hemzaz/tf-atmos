# ACM (AWS Certificate Manager) Component

This component manages SSL/TLS certificates for domains using AWS Certificate Manager. It supports both DNS and email validation methods, with strong validation to prevent misconfigurations.

## Usage

```hcl
component "acm" {
  instance = "domain"
  
  vars = {
    region     = "us-west-2"
    zone_id    = "Z1234567890ABCDEFGHIJ"  # Route53 hosted zone ID
    
    dns_domains = {
      "main" = {
        domain_name               = "example.com"
        subject_alternative_names = ["www.example.com", "api.example.com"]
        validation_method         = "DNS"
        wait_for_validation       = true
      },
      "wildcard" = {
        domain_name = "*.example.com"
        validation_method = "DNS"
      }
    }
    
    tags = {
      Environment = "dev"
      Owner       = "platform-team"
    }
  }
}
```

## Features

- Creates ACM certificates for multiple domains
- Support for subject alternative names (SANs)
- DNS or email validation methods
- Automatic Route53 record creation for DNS validation
- Extensive validation to prevent misconfigurations
- Certificate transparency logging control

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0.0 |
| aws | >= 4.0.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| region | AWS region | `string` | n/a | yes |
| zone_id | Route53 zone ID to create validation records in | `string` | n/a | yes |
| dns_domains | Map of domain configurations to create ACM certificates for | `map(object)` | `{}` | no |
| cert_transparency_logging | Whether to enable certificate transparency logging | `bool` | `true` | no |
| tags | Tags to apply to resources | `map(string)` | `{}` | no |

### dns_domains Object Structure

```hcl
{
  domain_name               = string
  subject_alternative_names = optional(list(string), [])
  validation_method         = optional(string, "DNS")
  wait_for_validation       = optional(bool, true)
  tags                      = optional(map(string), {})
}
```

## Outputs

| Name | Description |
|------|-------------|
| certificate_arns | Map of certificate ARNs by domain key |
| certificate_domains | Map of certificate domain names by domain key |
| certificate_statuses | Map of certificate validation statuses by domain key |

## Validation

This component includes extensive validation to prevent common errors:

1. Domain name format checking
2. Validation method must be "DNS" or "EMAIL"
3. Zone ID format validation
4. Subject alternative names format checking
5. Ensures Tags contain "Environment" key

## Timeouts

The certificate validation waits up to 45 minutes to account for DNS propagation delays.

## Notes

- For DNS validation, the component will automatically create Route53 records
- For EMAIL validation, you must respond to validation emails sent to the domain's WHOIS contact addresses
- Certificate validation may take up to 30 minutes to complete
- If using email validation, ensure the WHOIS contact information is up-to-date