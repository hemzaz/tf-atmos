# Environment Onboarding Guide

This guide will walk you through adding a new environment (like QA, UAT, or Staging) to your infrastructure managed with Atmos/Terraform. The process is simple and follows a template-based approach that doesn't require deep DevOps knowledge.

## Prerequisites

- Access to the Git repository
- Terraform installed (version 1.0.0 or higher)
  ```bash
  # MacOS with Homebrew
  brew install terraform
  
  # Windows with Chocolatey
  choco install terraform
  
  # Verify installation
  terraform --version
  ```

- Atmos CLI installed (version 1.5.0 or higher)
  ```bash
  # Install via Homebrew (recommended for macOS)
  brew tap cloudposse/tap
  brew install atmos
  
  # For Linux/macOS without Homebrew
  curl -fsSL https://atmos.tools/install.sh | bash
  
  # For Windows or alternative method
  # See https://atmos.tools/quick-start/ for detailed instructions
  
  # Verify installation
  atmos version
  ```

- AWS CLI installed and configured with appropriate permissions
  ```bash
  # Verify AWS CLI is configured correctly
  aws sts get-caller-identity
  ```

- A text editor of your choice (VSCode, IntelliJ, Sublime, etc.)
- Basic understanding of YAML files
- An existing environment to use as a template (e.g., testenv-01)
- A wildcard certificate in AWS Certificate Manager (ACM) for your domain

## Overview

Adding a new environment involves these easy steps:

1. Create a new environment directory
2. Copy and modify configuration files
3. Run the onboarding workflow
4. Set up certificates
5. Deploy the full environment
6. Verify the deployment

Let's walk through each step with examples for creating a "qa" environment.

## Step 1: Create a New Environment Directory

First, we'll create a new directory for the QA environment:

```bash
mkdir -p stacks/account/dev/qa-01
```

The directory structure will look like this:

```
stacks/
└── account/
    └── dev/
        ├── testenv-01/  # Existing environment
        │   ├── acm.yaml
        │   ├── apigateway.yaml
        │   ├── backend.yaml
        │   ├── eks.yaml
        │   ├── external-secrets.yaml  # Important for certificate management
        │   ├── iam.yaml
        │   ├── infrastructure.yaml
        │   ├── network.yaml
        │   ├── secretsmanager.yaml
        │   ├── services.yaml
        │   └── variables.yaml
        └── qa-01/     # New environment (to be created)
```

## Step 2: Copy and Modify Configuration Files

Copy the configuration files from the existing environment:

```bash
# For MacOS/Linux
cp stacks/account/dev/testenv-01/*.yaml stacks/account/dev/qa-01/

# For Windows PowerShell
Copy-Item stacks/account/dev/testenv-01/*.yaml -Destination stacks/account/dev/qa-01/
```

### Edit Variables File

Edit the `variables.yaml` file first to set environment-specific settings:

Open `stacks/account/dev/qa-01/variables.yaml` in your preferred text editor. For example:
- VSCode: `code stacks/account/dev/qa-01/variables.yaml`
- IntelliJ: File > Open
- Sublime: `subl stacks/account/dev/qa-01/variables.yaml`

Before changing:
```yaml
##################################################
# Environment-specific Variables
##################################################

# Domain name and infrastructure
domain_name: "example.com"
hosted_zone_id: "Z1234567890EXAMPLE"

# Certificate management
use_external_secrets: true  # Using external-secrets operator for certificate management
secrets_manager_path_prefix: "myapp/testenv-01/certificates"
```

After changing:
```yaml
##################################################
# Environment-specific Variables
##################################################

# Domain name and infrastructure
domain_name: "example.com"
hosted_zone_id: "Z1234567890EXAMPLE"

# Certificate management
use_external_secrets: true  # Using external-secrets operator for certificate management
secrets_manager_path_prefix: "myapp/qa-01/certificates"
```

### Update Environment-Specific References

You'll need to update all environment-specific references in each file. Most editors have search and replace functionality to help with this task:

1. Use search and replace to find all instances of "testenv-01" and replace with "qa-01" 
2. Look for resource names that include "testenv" and replace with "qa"

Here are the key files to update:

Open `eks.yaml` and change:
```yaml
# Change this:
karpenter:
  enabled: true
  set_values:
    settings.aws.clusterName: "testenv-01-main"
    settings.aws.clusterEndpoint: ${output.eks.cluster_endpoints.main}
    settings.aws.defaultInstanceProfile: "testenv-01-karpenter-node-profile"
    
# To this:
karpenter:
  enabled: true
  set_values:
    settings.aws.clusterName: "qa-01-main"
    settings.aws.clusterEndpoint: ${output.eks.cluster_endpoints.main}
    settings.aws.defaultInstanceProfile: "qa-01-karpenter-node-profile"
```

Open `secretsmanager.yaml` and change:
```yaml
# Change this:
secretsmanager_app_db:
  vars:
    secrets:
      db_credentials:
        description: "MyApp database credentials for testenv-01"

# To this:
secretsmanager_app_db:
  vars:
    secrets:
      db_credentials:
        description: "MyApp database credentials for qa-01"
```

Open `external-secrets.yaml` and verify the settings:
```yaml
external-secrets:
  vars:
    namespace: "external-secrets"
    create_namespace: true
    certificate_secret_path_template: "certificates/{name}"
    create_default_cluster_secret_store: true
    create_certificate_secret_store: true
    tags:
      Environment: ${environment}  # This will resolve to qa-01
```

In `monitoring.yaml`, update dashboard names:
```yaml
# Change dashboard names
monitoring:
  vars:
    dashboards:
      infrastructure:
        name: "qa-01-infrastructure"  # Was testenv-01-infrastructure
```

**Tip**: Most modern code editors offer "Find and Replace in Files" functionality that can help you quickly find all occurrences of "testenv-01" across all copied files and replace them with "qa-01" in a single operation.

## Step 3: Create Required AWS Resources

Before running the onboarding workflow, make sure you have:

1. A Route53 Hosted Zone for your domain
2. An ACM Certificate for your domain (wildcard recommended)

You can verify with:
```bash
# Check your hosted zones
aws route53 list-hosted-zones

# Check your certificates (make sure to check in the correct region)
aws acm list-certificates --region eu-west-2
```

> **Important**: ACM certificates are region-specific. Make sure your certificate is created in the same region where you'll be deploying your infrastructure. The region specified in your environment configuration files is in `stacks/account/dev/qa-01/variables.yaml` (typically the `region` variable).

If you need to create a new certificate:

```bash
# Request a new certificate (for *.example.com)
aws acm request-certificate \
  --domain-name "*.example.com" \
  --validation-method DNS \
  --region eu-west-2
```

For validation, you'll need to create a CNAME record in your DNS. Follow the instructions in the AWS console or use the CLI to get validation details.

## Step 4: Run the Onboarding Workflow

Now run the onboarding workflow to create the base environment:

```bash
atmos workflow onboard-environment tenant=fnx account=dev environment=qa-01 vpc_cidr=10.1.0.0/16 domain_name=example.com
```

Example output:
```
[INFO] Starting environment onboarding workflow
[INFO] Creating environment: qa-01
[INFO] Creating VPC with CIDR 10.1.0.0/16
[INFO] Creating base network infrastructure
[INFO] Creating subnets
[INFO] Configuring routing tables
[INFO] Deploying IAM roles and policies
[INFO] Setting up backend storage
[INFO] Environment qa-01 created successfully
[INFO] Next steps:
[INFO] - Run 'atmos workflow plan-environment tenant=fnx account=dev environment=qa-01' to preview the full environment
[INFO] - Run 'atmos workflow apply-environment tenant=fnx account=dev environment=qa-01' to deploy the environment
```

## Step 5: Set Up Certificates

The next step is to set up certificates for the environment. This must be done **before** deploying the full environment:

### 5.1 Deploy ACM Component

First, deploy the ACM component which will create or import certificates:

```bash
atmos terraform apply acm -s fnx-dev-qa-01
```

After ACM is deployed, get the ARN of your wildcard certificate:

```bash
aws acm list-certificates --query 'CertificateSummaryList[?DomainName==`*.example.com`].CertificateArn' --output text
```

### 5.2 Export Certificate to Secrets Manager

Export your certificate to AWS Secrets Manager:

> **Note**: This step requires you to have the certificate's private key file if it was imported into ACM. For ACM-issued certificates, this step may be more complex - see the [Secrets Manager Guide](docs/secrets-manager-guide.md) for details.

```bash
# Make sure the script is executable
chmod +x ./scripts/certificates/export-cert.sh  # For MacOS/Linux only

# Export certificate
./scripts/certificates/export-cert.sh \
  -a arn:aws:acm:eu-west-2:123456789012:certificate/abcd1234-abcd-1234-abcd-1234567890ab \
  -r eu-west-2 \
  -o ./certs \
  -s certificates/wildcard-qa-01-example-com-cert
```

Example output:
```
Exporting certificate from ACM...
ARN: arn:aws:acm:eu-west-2:123456789012:certificate/abcd1234-abcd-1234-abcd-1234567890ab
Region: eu-west-2
Domain: *.example.com
Status: ISSUED
Type: IMPORTED
Expires: 2026-02-28 12:00:00
Exporting certificate data...
This is an imported certificate. You must have the private key that was originally used to import the certificate.
Please provide the private key file when prompted, or press Ctrl+C to cancel.
Enter path to the private key file: /path/to/your/key.pem
Private key saved to ./certs/_wildcard_example.com/tls.key
✅ Certificate stored in AWS Secrets Manager as certificates/wildcard-qa-01-example-com-cert
Export completed successfully!
Files are available in: ./certs/_wildcard_example.com
```

> **Important**: For Windows users, you may need to run this script in Git Bash or WSL. The script may not work correctly in PowerShell.

### 5.3 Update EKS Configuration to Use the Certificate

Now update the secrets path in your eks.yaml file using your code editor:

Open `stacks/account/dev/qa-01/eks.yaml` and edit the line that specifies the secret path:

```yaml
# Change this line:
secrets_manager_secret_path: "certificates/wildcard-${var.domain_name}-cert"

# To this specific path matching what you created:
secrets_manager_secret_path: "certificates/wildcard-qa-01-example-com-cert"
```

## Step 6: Deploy the Full Environment

Now deploy the full environment. There are two approaches you can use:

### Option 1: Step-by-step deployment (recommended for first-time setup)

This approach gives you more control and makes it easier to troubleshoot issues:

```bash
# First deploy backend and networking components
atmos terraform apply backend -s fnx-dev-qa-01
atmos terraform apply network -s fnx-dev-qa-01
atmos terraform apply iam -s fnx-dev-qa-01

# Then deploy secrets management (important for certificate handling)
atmos terraform apply secretsmanager -s fnx-dev-qa-01
atmos terraform apply external-secrets -s fnx-dev-qa-01

# Finally deploy EKS and other components
atmos terraform apply eks -s fnx-dev-qa-01
atmos terraform apply eks-addons -s fnx-dev-qa-01
atmos terraform apply monitoring -s fnx-dev-qa-01
```

> **Note**: The order is important because of component dependencies. For example, external-secrets must be deployed before eks-addons to properly handle certificates.

### Option 2: Use the workflow (faster but harder to troubleshoot)

Alternatively, you can use the apply-environment workflow, which will handle the ordering for you:

```bash
atmos workflow apply-environment tenant=fnx account=dev environment=qa-01
```

If you encounter errors with this approach, it's recommended to fall back to the step-by-step method to better identify the specific issue.

Example output:
```
[INFO] Starting environment apply workflow
[INFO] Applying network component
...
Apply complete! Resources: 47 added, 0 changed, 0 destroyed.
[INFO] Network component applied successfully
[INFO] Applying IAM component
...
Apply complete! Resources: 12 added, 0 changed, 0 destroyed.
[INFO] IAM component applied successfully
...
[INFO] Applying secretsmanager component
...
Apply complete! Resources: 8 added, 0 changed, 0 destroyed.
[INFO] secretsmanager component applied successfully
[INFO] Applying external-secrets component
...
Apply complete! Resources: 6 added, 0 changed, 0 destroyed.
[INFO] external-secrets component applied successfully
[INFO] Applying eks component
...
Apply complete! Resources: 23 added, 0 changed, 0 destroyed.
[INFO] eks component applied successfully
...
[INFO] Environment qa-01 deployed successfully
```

## Step 7: Verify the Deployment

Verify that all components deployed successfully:

```bash
# Check the EKS cluster status
aws eks describe-cluster --name qa-01-main --region eu-west-2

# Check if Kubernetes can be accessed
aws eks update-kubeconfig --name qa-01-main --region eu-west-2
kubectl get nodes
```

Example EKS cluster output:
```json
{
  "cluster": {
    "name": "qa-01-main",
    "arn": "arn:aws:eks:eu-west-2:123456789012:cluster/qa-01-main",
    "createdAt": "2025-02-28T10:15:22.000000+00:00",
    "version": "1.28",
    "endpoint": "https://A1B2C3D4E5F6G7H8I9J0.gr7.eu-west-2.eks.amazonaws.com",
    "roleArn": "arn:aws:iam::123456789012:role/qa-01-eks-cluster-role",
    "resourcesVpcConfig": {
      "subnetIds": [
        "subnet-0abc123def456789",
        "subnet-0def456789abc123",
        "subnet-0123456789abcdef"
      ],
      "vpcId": "vpc-0abcdef123456789"
    },
    "status": "ACTIVE"
  }
}
```

Verify certificate setup:
```bash
# Check if ExternalSecret exists for certificate
kubectl get externalsecret -n istio-ingress

# Check if Secret exists with certificate
kubectl get secret istio-gateway-cert -n istio-ingress
```

## Step 8: Create Required SSM Parameters

Some components may need SSM parameters to function correctly:

```bash
# Create a parameter for Grafana admin password
aws ssm put-parameter \
  --name "/qa-01/grafana/admin-password" \
  --value "YourSecurePassword123!" \
  --type "SecureString" \
  --description "Grafana admin password for qa-01" \
  --overwrite
```

## Environment Naming Conventions

Use these naming conventions for consistency:

| Environment Type | Naming Pattern | Example |
|------------------|----------------|---------|
| Development      | dev-##         | dev-01  |
| QA               | qa-##          | qa-01   |
| Staging          | stage-##       | stage-01|
| UAT              | uat-##         | uat-01  |
| Production       | prod-##        | prod-01 |

## Common Issues and Solutions

### Deployment Issues

**Issue**: Subnet conflict error during deployment  
**Solution**: Change the VPC CIDR to a non-overlapping range
```bash
# Modify your command to use a different CIDR
atmos workflow onboard-environment tenant=fnx account=dev environment=qa-01 vpc_cidr=10.2.0.0/16 domain_name=example.com
```

**Issue**: EKS cluster fails to create  
**Solution**: 
1. Check IAM permissions (need admin or PowerUserAccess)
2. Verify VPC subnet configuration
3. Check the CloudTrail logs for specific errors
```bash
# View recent CloudTrail events for EKS
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventSource,AttributeValue=eks.amazonaws.com
```

### Certificate and Secret Management Issues

**Issue**: Certificate not found error in EKS  
**Solution**: 
1. Verify the certificate path in eks.yaml matches exactly what you created in Step 5.2
2. Check that external-secrets is deployed before eks-addons
3. Run `kubectl describe externalsecret -n istio-ingress` to see any sync issues
4. Check Secrets Manager to ensure the certificate was properly stored:
```bash
aws secretsmanager list-secrets --filter Key=name,Values=certificates/wildcard
```

**Issue**: "Grafana admin password parameter not found" error  
**Solution**: Create the SSM parameter as shown in Step 8
```bash
aws ssm put-parameter --name "/qa-01/grafana/admin-password" --value "SecurePassword123!" --type "SecureString"
```

**Issue**: Missing ACM certificate issues  
**Solution**: 
1. Verify the certificate exists in ACM
2. Ensure it's in the correct region
3. Note that ACM certificates are region-specific
```bash
# Check certificates in all regions
for region in $(aws ec2 describe-regions --query "Regions[].RegionName" --output text); do 
  echo "Region: $region"; 
  aws acm list-certificates --region $region; 
done
```

**Issue**: External-secrets not syncing certificates
**Solution**:
1. Check the external-secrets operator logs
2. Verify IAM permissions for the service account
3. Ensure the ClusterSecretStore is properly configured
```bash
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets
kubectl get clustersecretstore aws-certificate-store -o yaml
```

## Support and Additional Resources

If you encounter issues, please refer to:

- **Project Documentation**:
  - [Certificate Management Guide](../docs/secrets-manager-guide.md)
  - [EKS Addons Reference](../docs/eks-addons-reference.md)
  - [Component Creation Guide](../docs/component-creation-guide.md)

- **AWS Documentation**:
  - [AWS EKS Documentation](https://docs.aws.amazon.com/eks)
  - [AWS ACM Documentation](https://docs.aws.amazon.com/acm)
  - [AWS Secrets Manager Documentation](https://docs.aws.amazon.com/secretsmanager)
  - [AWS SSM Parameter Store Documentation](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html)

- **Terraform and Atmos**:
  - [Terraform Documentation](https://www.terraform.io/docs)
  - [Atmos Documentation](https://atmos.tools/quick-start/)
  - [Terraform Registry for AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

- **Support Channels**:
  - Internal knowledge base: https://kb.example.com/atmos
  - Cloud Team Slack channel: #cloud-infrastructure
  - Open a support ticket: helpdesk@example.com