# Certificate Management Guide

_Last Updated: March 10, 2025_

This guide covers TLS/SSL certificate management with Atmos, including ACM certificate provisioning, validation, rotation, and monitoring.

## Table of Contents

- [Overview](#overview)
- [ACM Component](#acm-component)
- [Certificate Validation](#certificate-validation)
- [Certificate Management Patterns](#certificate-management-patterns)
- [Certificate Rotation](#certificate-rotation)
- [Certificate Monitoring](#certificate-monitoring)
- [External Secrets Integration](#external-secrets-integration)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

## Overview

Proper certificate management is critical for securing applications and services. Atmos provides comprehensive tools for managing certificates through AWS Certificate Manager (ACM) and integrates with External Secrets Operator for Kubernetes deployments.

Key features include:

1. **ACM Certificate Management** - Provision and manage ACM certificates
2. **DNS Validation** - Automated DNS validation via Route 53
3. **Certificate Rotation** - Scheduled and on-demand certificate rotation
4. **Certificate Monitoring** - Expiration monitoring and alerting
5. **Kubernetes Integration** - Certificate usage in Kubernetes via External Secrets

## ACM Component

The ACM component manages certificates through AWS Certificate Manager:

```yaml
components:
  terraform:
    acm:
      vars:
        enabled: true
        dns_domain_name: "example.com"
        
        # Domain configurations
        dns_domains:
          # Wildcard certificate for main domain
          wildcard:
            domain_name: "*.example.com"
            subject_alternative_names:
              - "example.com"
            validation_method: "DNS"
            wait_for_validation: true
            
          # API certificate
          api:
            domain_name: "api.example.com"
            validation_method: "DNS"
            wait_for_validation: true
            
        # Validation options
        validation_method: "DNS"
        zone_id: "${output.dns.hosted_zone_id}"
        wait_for_validation: true
        
        # Monitoring and alerts
        enable_expiration_monitoring: true
        expiration_threshold_days: 30
        alarm_actions:
          - "${output.sns.alerts_topic_arn}"
```

### Multiple ACM Certificates

Using the multiple component instances pattern, you can manage different certificate groups:

```yaml
components:
  terraform:
    acm/main:
      vars:
        enabled: true
        dns_domains:
          wildcard:
            domain_name: "*.example.com"
            subject_alternative_names:
              - "example.com"
        # ...
    
    acm/internal:
      vars:
        enabled: true
        dns_domains:
          internal:
            domain_name: "*.internal.example.com"
        # ...
```

## Certificate Validation

Atmos supports two validation methods:

### DNS Validation (Recommended)

DNS validation automatically creates the required DNS records in Route 53:

```yaml
acm:
  vars:
    validation_method: "DNS"
    zone_id: "${output.dns.hosted_zone_id}"
    wait_for_validation: true
```

### Email Validation

Email validation sends verification emails to domain contacts:

```yaml
acm:
  vars:
    validation_method: "EMAIL"
    wait_for_validation: false  # Cannot wait for email validation
```

## Certificate Management Patterns

### Single-Region Certificates

Basic ACM certificate in a single region:

```yaml
acm:
  vars:
    enabled: true
    region: "us-west-2"
    dns_domains:
      main:
        domain_name: "*.example.com"
```

### Multi-Region Certificates

For services that need certificates in multiple regions (e.g., CloudFront with API Gateway):

```yaml
acm:
  vars:
    enabled: true
    region: "us-east-1"  # Primary region
    enable_cross_region_replication: true
    target_regions:
      - "us-west-2"
      - "eu-west-1"
    dns_domains:
      cdn:
        domain_name: "cdn.example.com"
```

### Imported Certificates

Import existing certificates:

```yaml
acm:
  vars:
    enabled: true
    imported_certificates:
      legacy:
        certificate_body: "${file(certs/legacy.crt)}"
        private_key: "${file(certs/legacy.key)}"
        certificate_chain: "${file(certs/legacy_chain.crt)}"
```

## Certificate Rotation

Atmos includes workflows for certificate rotation:

```bash
# Rotate certificate
atmos workflow rotate-certificate \
  tenant=mycompany \
  account=prod \
  environment=prod-01 \
  domain=example.com \
  certificate_id=arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012
```

### Automated Rotation Workflow

```yaml
name: rotate-certificate
description: "Rotate an ACM certificate"

workflows:
  rotate:
    description: "Rotate a certificate in ACM"
    steps:
    - run:
        command: |
          if [ -z "${tenant}" ] || [ -z "${account}" ] || [ -z "${environment}" ] || [ -z "${domain}" ]; then
            echo "ERROR: Missing required parameters."
            echo "Usage: atmos workflow rotate-certificate tenant=<tenant> account=<account> environment=<environment> domain=<domain> [certificate_id=<arn>]"
            exit 1
          fi
          
          # Find certificate if ARN not provided
          if [ -z "${certificate_id}" ]; then
            echo "Finding certificate for domain ${domain}"
            CERTIFICATE_ID=$(aws acm list-certificates --query "CertificateSummaryList[?DomainName=='${domain}'].CertificateArn" --output text)
            if [ -z "$CERTIFICATE_ID" ]; then
              echo "ERROR: Could not find certificate for domain ${domain}"
              exit 1
            fi
          else
            CERTIFICATE_ID="${certificate_id}"
          fi
          
          # Request certificate renewal
          echo "Requesting renewal for certificate ${CERTIFICATE_ID}"
          aws acm renew-certificate --certificate-arn "${CERTIFICATE_ID}"
          
          # Wait for renewal to complete
          echo "Waiting for certificate renewal to complete..."
          aws acm wait certificate-validated --certificate-arn "${CERTIFICATE_ID}"
          
          echo "Certificate ${CERTIFICATE_ID} has been rotated successfully."
```

## Certificate Monitoring

Atmos includes CloudWatch alarms for certificate expiration monitoring:

```yaml
acm:
  vars:
    enable_expiration_monitoring: true
    expiration_threshold_days: 30
    alarm_actions:
      - "${output.sns.alerts_topic_arn}"
    insufficient_data_actions:
      - "${output.sns.alerts_topic_arn}"
```

Dashboards are created to monitor certificate status:

```yaml
monitoring:
  vars:
    enable_certificate_monitoring: true
    certificate_arns: ${output.acm.certificate_arns}
    certificate_domains: ${output.acm.certificate_domains}
    certificate_expiry_threshold: 30
    dashboard_name: "certificate-monitoring"
```

## External Secrets Integration

Atmos integrates ACM certificates with Kubernetes using External Secrets Operator:

```yaml
components:
  terraform:
    external-secrets:
      vars:
        enabled: true
        cluster_name: "${output.eks.cluster_ids.main}"
        oidc_provider_arn: "${output.eks.oidc_provider_arns.main}"
        
        # Certificate store configuration
        certificate_store:
          path_template: "certificates/{name}"
        
        secret_stores:
          default_cluster:
            create: true
          certificate:
            create: true
```

### Certificate Secret Example

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: tls-cert
  namespace: istio-system
spec:
  refreshInterval: "1h"
  secretStoreRef:
    name: certificate-store
    kind: ClusterSecretStore
  target:
    name: tls-cert
    creationPolicy: Owner
  data:
  - secretKey: tls.crt
    remoteRef:
      key: certificates/example.com-wildcard
      property: certificate
  - secretKey: tls.key
    remoteRef:
      key: certificates/example.com-wildcard
      property: private_key
```

## Best Practices

### General

1. **Use DNS Validation** - Always use DNS validation when possible
2. **Wait For Validation** - Set `wait_for_validation: true` for complete provisioning
3. **Wildcard Certificates** - Use wildcards to cover multiple subdomains
4. **Expiration Monitoring** - Always enable expiration monitoring
5. **Renewal Planning** - Plan for certificate renewal well before expiration

### Security

1. **Least Privilege** - Use minimal IAM permissions for certificate management
2. **Private Keys** - Never export private keys from ACM when possible
3. **Imported Certificates** - Securely manage private keys for imported certificates
4. **Key Length** - Use 2048-bit or stronger RSA keys
5. **Logging** - Enable CloudTrail for certificate operations

### Operational

1. **Documentation** - Document certificate mappings and usage
2. **Rotation Process** - Implement automated certificate rotation
3. **Certificate Inventory** - Maintain inventory of all certificates
4. **Testing** - Test certificate renewal process before production
5. **Cross-Region** - Use cross-region replication for global services

## Troubleshooting

### Certificate Validation Issues

1. **DNS Validation Failures**
   - Verify Route 53 zone ID is correct
   - Check for DNS propagation issues
   - Verify IAM permissions for DNS record creation
   - Check for conflicting DNS records

2. **Email Validation Issues**
   - Verify domain contacts are correct
   - Check spam folders for validation emails
   - Resend validation emails if needed

### Certificate Usage Issues

1. **Certificate Association Failures**
   - Verify certificate ARN is correct
   - Check that certificate is in the same region as the service
   - Verify certificate includes the required domain names
   - Check that the certificate is fully validated

2. **TLS Errors**
   - Verify certificate chain is complete
   - Check for SNI support in clients
   - Verify certificate is not expired
   - Validate cipher suite compatibility

### Kubernetes Certificate Issues

1. **External Secrets Issues**
   - Verify IRSA permissions for Secret Store
   - Check Secret Store configuration
   - Verify ExternalSecret resource syntax
   - Check pod logs for External Secrets Operator

2. **Certificate Mounting Issues**
   - Verify Secret exists and has correct keys
   - Check volume mount configuration
   - Validate file permissions in container
   - Check pod events for volume mounting errors

### Diagnostic Commands

```bash
# Check ACM certificate status
aws acm describe-certificate --certificate-arn <arn>

# List certificates
aws acm list-certificates

# Check Route 53 validation records
aws route53 list-resource-record-sets --hosted-zone-id <zone-id> --query "ResourceRecordSets[?Type=='CNAME']"

# Check CloudWatch alarm status
aws cloudwatch describe-alarms --alarm-names "CertificateExpiry-example.com"

# Verify External Secrets in Kubernetes
kubectl get externalsecrets -A
kubectl get secretstores -A
kubectl describe externalsecret tls-cert -n istio-system
```