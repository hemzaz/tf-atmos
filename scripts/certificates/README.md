# Certificate Management Helper Scripts

These scripts provide automation for certificate management, export, and rotation in AWS ACM and Kubernetes environments.

## Overview

The scripts in this directory help with:

1. Exporting certificates from AWS ACM
2. Integrating with External Secrets Operator for automatic certificate rotation
3. Monitoring certificate expiry dates and statuses

## Scripts

### export-cert.sh

Exports certificate metadata from AWS ACM and creates templates for Kubernetes Secrets and ExternalSecrets.

```bash
# Usage
./export-cert.sh -a <acm_certificate_arn> -r <aws_region> -o <output_directory> [-p <aws_profile>]

# Example
./export-cert.sh -a arn:aws:acm:us-west-2:123456789012:certificate/abcd1234-a123-456b-789c-0123456789ab \
                -r us-west-2 \
                -o ./certs \
                -p my-aws-profile
```

### rotate-cert.sh

Rotates certificates by updating the reference to a new ACM certificate, using External Secrets.

```bash
# Usage
./rotate-cert.sh -a <acm_certificate_arn> -r <aws_region> -k <k8s_namespace>/<k8s_secret_name> \
                [-p <aws_profile>] [-c <k8s_context>] -e

# Example
./rotate-cert.sh -a arn:aws:acm:us-west-2:123456789012:certificate/abcd1234-a123-456b-789c-0123456789ab \
                -r us-west-2 \
                -k istio-ingress/example-com-tls \
                -p my-aws-profile \
                -c my-eks-cluster \
                -e
```

## Integration with External Secrets

These scripts are designed to work with the External Secrets Operator, which should be deployed separately using the `external-secrets` Terraform component. The workflow is:

1. Create/import certificates in AWS ACM
2. Use the scripts to export certificate metadata and create Secret Manager reference
3. Create ExternalSecret resources to map AWS Secrets Manager secrets to Kubernetes Secrets
4. External Secrets automatically syncs the certificate data to Kubernetes

## Notes

- AWS ACM does not allow direct export of private keys for certificates managed by ACM
- For ACM-managed certificates, External Secrets is the recommended approach
- For imported certificates, the scripts provide a structured export process
- These scripts require the AWS CLI, jq, and kubectl to be installed and configured

## Security Considerations

- Certificates are sensitive information and should be handled securely
- The scripts do not output private key material to logs or console
- AWS IAM permissions should follow the principle of least privilege
- Consider using the monitoring dashboards created by the `monitoring` component to track certificate expiry