# Certificate Management Helper Scripts

These scripts provide automation for certificate management, export, and rotation in AWS environments and Kubernetes clusters.

## Overview

The scripts in this directory help with:

1. Exporting certificates from AWS ACM for use with Kubernetes and other services
2. Rotating certificates in AWS ACM and Kubernetes clusters
3. Exporting SSH keys from AWS Secrets Manager for secure access to EC2 instances
4. Integrating with External Secrets Operator for automated secret management

All scripts use the portable shebang `#!/usr/bin/env bash` for cross-platform compatibility and work on Linux, macOS, and Windows (with Git Bash or WSL).

## Scripts

### export-cert.sh

Exports certificates from AWS ACM and prepares them for use with Kubernetes secrets and AWS Secrets Manager.

#### Requirements

- AWS CLI installed and configured
- jq installed
- openssl installed
- Valid permissions to access ACM certificates
- Tool versions defined in the project's `.env` file

#### Options

| Option | Description |
|--------|-------------|
| `-a, --arn ARN` | ARN of the ACM certificate to export (required) |
| `-r, --region REGION` | AWS region (defaults to AWS_REGION env var or aws configure default) |
| `-o, --output DIR` | Output directory for certificate files (default: ./exported-certificates) |
| `-s, --secret-name NAME` | Name of the secret in AWS Secrets Manager (default: certificates/domain-name) |
| `-u, --upload` | Upload certificate to AWS Secrets Manager |
| `-h, --help` | Show help message |

#### Example Usage

```bash
#!/usr/bin/env bash
# Basic usage
./export-cert.sh -a arn:aws:acm:us-west-2:123456789012:certificate/abcd1234-abcd-1234-abcd-1234abcd5678

# Export and upload to AWS Secrets Manager
./export-cert.sh -a arn:aws:acm:us-west-2:123456789012:certificate/abcd1234 -o /tmp/certs -u

# Specify custom secret name
./export-cert.sh -a arn:aws:acm:us-west-2:123456789012:certificate/abcd1234 -s custom/secret/path -u
```

### rotate-cert.sh

Helps with rotation of certificates in AWS ACM and updates Kubernetes secrets using External Secrets Operator.

#### Requirements

- AWS CLI installed and configured
- kubectl installed and configured (version from `.env` file)
- jq installed
- Valid permissions to access ACM and Secrets Manager
- Tool versions defined in the project's `.env` file

#### Options

| Option | Description |
|--------|-------------|
| `-s SECRET_NAME` | AWS Secret name in Secrets Manager (required) |
| `-n NAMESPACE` | Kubernetes namespace for the secret (required) |
| `-a ARN` | New AWS ACM Certificate ARN (optional) |
| `-r REGION` | AWS Region (default: current region) |
| `-c CONTEXT` | Kubernetes context (optional) |
| `-k K8S_SECRET` | Kubernetes secret name (default: derived from secret name) |
| `-p PROFILE` | AWS CLI profile (optional) |
| `-h` | Display help message |

#### Example Usage

```bash
#!/usr/bin/env bash
# Rotate certificate with a new ACM certificate
./rotate-cert.sh -s certificates/example-com -n istio-system -a arn:aws:acm:us-west-2:123456789012:certificate/abcd1234

# Rotate certificate with custom Kubernetes secret name
./rotate-cert.sh -s certificates/example-com -n istio-system -k example-com-tls -a arn:aws:acm:us-west-2:123456789012:certificate/abcd1234

# Force refresh of ExternalSecret without changing certificate
./rotate-cert.sh -s certificates/example-com -n istio-system
```

### export-ssh-key.sh

Downloads SSH keys from AWS Secrets Manager for secure access to EC2 instances.

#### Requirements

- AWS CLI installed and configured
- jq installed
- Valid permissions to access Secrets Manager
- Tool versions defined in the project's `.env` file

#### Options

| Option | Description |
|--------|-------------|
| `-r, --region` | AWS region (default: us-west-2) |
| `-p, --profile` | AWS profile (default: default) |
| `-s, --secret-id` | Secret ID/name in AWS Secrets Manager (required) |
| `-i, --instance-id` | EC2 instance ID (optional, needed for instance-specific keys) |
| `-o, --output-file` | Output file path (default: ./id_rsa) |
| `-f, --force` | Force overwrite if output file exists |
| `-h, --help` | Display help message |

#### Example Usage

```bash
#!/usr/bin/env bash
# Basic usage
./export-ssh-key.sh -s dev/ec2/ssh-keys -o ~/.ssh/my_key

# With custom region and profile
./export-ssh-key.sh -r us-east-1 -p myprofile -s dev/ec2/ssh-keys -o ~/.ssh/my_key

# Extract instance-specific key
./export-ssh-key.sh -s dev/ec2/ssh-keys -i i-01234567890abcdef -o ~/.ssh/instance_key

# Force overwrite existing key
./export-ssh-key.sh -s dev/ec2/ssh-keys -o ~/.ssh/my_key -f
```

## Integration with External Secrets

These scripts are designed to work with the External Secrets Operator, which should be deployed separately using the `external-secrets` Terraform component. The workflow is:

1. Create/import certificates in AWS ACM
2. Use the scripts to export certificate metadata and create Secret Manager reference
3. Create ExternalSecret resources to map AWS Secrets Manager secrets to Kubernetes Secrets
4. External Secrets automatically syncs the certificate data to Kubernetes

## Security Considerations

- Certificates and SSH keys are sensitive information and should be handled securely
- The scripts do not output private key material to logs or console
- Private keys are temporarily stored on disk with restricted permissions (600)
- AWS IAM permissions should follow the principle of least privilege
- Consider using the monitoring dashboards created by the `monitoring` component to track certificate expiry

## Notes

- AWS ACM does not allow direct export of private keys for certificates managed by ACM
- For ACM-managed certificates, External Secrets is the recommended approach
- For imported certificates, the scripts provide a structured export process
- These scripts require the AWS CLI, jq, and kubectl to be installed and configured (versions specified in the `.env` file)
- All scripts are cross-platform compatible with Linux, macOS, and Windows (Git Bash/WSL)
- SSH keys stored in Secrets Manager can be structured for environment-wide access or instance-specific access
- Version information for required tools is centralized in the `.env` file in the project root