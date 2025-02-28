# Terraform/Atmos Troubleshooting Guide

This guide provides solutions for common issues you might encounter when working with the Terraform and Atmos components in this codebase. Each section includes error symptoms, causes, and step-by-step solutions.

## Table of Contents

1. [Certificate Management Issues](#certificate-management-issues)
2. [EKS Cluster Issues](#eks-cluster-issues)
3. [EKS Addons Deployment Issues](#eks-addons-deployment-issues)
4. [IAM and Permission Issues](#iam-and-permission-issues)
5. [Networking and Connectivity Issues](#networking-and-connectivity-issues)
6. [Terraform State Management](#terraform-state-management)
7. [Atmos Component Configuration](#atmos-component-configuration)

---

## Certificate Management Issues

### Error: "Certificate validation timed out"

**Symptoms:**
- ACM certificate creation gets stuck in the "pending validation" state
- Terraform doesn't complete after 45+ minutes

**Causes:**
- DNS validation records not properly created or propagated
- Route53 zone ID mismatch
- Incorrect domain format

**Solution:**

1. Check that the domain name is correctly formatted:
   ```
   # Correct format
   domain_name = "example.com"
   
   # Incorrect formats
   domain_name = "https://example.com"  # Remove https://
   domain_name = "example.com/"         # Remove trailing slash
   ```

2. Verify the Route53 zone ID matches the domain:
   ```bash
   aws route53 list-hosted-zones | grep -A1 -B1 "example.com"
   ```

3. Check if DNS validation records exist:
   ```bash
   aws route53 list-resource-record-sets --hosted-zone-id YOUR_ZONE_ID | grep acm
   ```

4. If records don't exist, check the ACM certificate:
   ```bash
   aws acm list-certificates
   aws acm describe-certificate --certificate-arn YOUR_CERT_ARN
   ```

5. For stubborn issues, create DNS validation records manually:
   ```bash
   aws acm describe-certificate --certificate-arn YOUR_CERT_ARN --query 'Certificate.DomainValidationOptions'
   # Note the RecordName, RecordType, and RecordValue
   
   aws route53 change-resource-record-sets --hosted-zone-id YOUR_ZONE_ID --change-batch '{
     "Changes": [
       {
         "Action": "UPSERT",
         "ResourceRecordSet": {
           "Name": "RECORD_NAME",
           "Type": "RECORD_TYPE",
           "TTL": 60,
           "ResourceRecords": [
             {
               "Value": "RECORD_VALUE"
             }
           ]
         }
       }
     ]
   }'
   ```

### Error: "Cannot use certificate with External Secrets"

**Symptoms:**
- External Secrets operator fails to retrieve certificates
- Error message about invalid certificate format
- Istio gateways fail to start with TLS errors

**Causes:**
- Certificate wasn't properly exported from ACM
- Certificate format issue in Secrets Manager
- Secret path mismatch

**Solution:**

1. Check the certificate export format:
   ```bash
   # Use our certificate export script
   ./scripts/certificates/export-cert.sh CERT_ARN
   ```

2. Verify certificate is stored correctly in Secrets Manager:
   ```bash
   aws secretsmanager get-secret-value --secret-id your/secret/path
   ```

3. Ensure the certificate contains both certificate and private key:
   ```
   # Correct format
   {
     "tls.crt": "-----BEGIN CERTIFICATE-----\n...",
     "tls.key": "-----BEGIN PRIVATE KEY-----\n..."
   }
   ```

4. If using cert-manager, check clusterissuer and certificate status:
   ```bash
   kubectl get clusterissuer
   kubectl get certificate -A
   kubectl describe certificate my-cert -n istio-system
   ```

---

## EKS Cluster Issues

### Error: "EKS cluster creation stuck"

**Symptoms:**
- EKS cluster creation hangs for more than 30 minutes
- `No output has been received in the last 10m0s` message

**Causes:**
- VPC or subnet issues
- IAM permission problems
- Security group or network ACL restrictions

**Solution:**

1. Check if subnets have proper tags:
   ```bash
   aws ec2 describe-subnets --subnet-ids subnet-1,subnet-2 --query 'Subnets[].Tags'
   ```
   
   Required tags:
   - For public subnets: `kubernetes.io/role/elb: 1`
   - For private subnets: `kubernetes.io/role/internal-elb: 1`

2. Verify subnet has internet access:
   ```bash
   # Check route tables
   aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=subnet-id"
   ```

3. Check security groups:
   ```bash
   aws ec2 describe-security-groups --group-ids sg-id
   ```
   
   Make sure required ports are open:
   - 443/tcp for API server
   - 10250/tcp for kubelet
   - 53/udp for CoreDNS

4. Verify IAM permissions:
   ```bash
   aws iam get-role --role-name eks-cluster-role
   aws iam simulate-principal-policy --policy-source-arn ROLE_ARN --action-names ec2:CreateSecurityGroup ec2:DescribeSubnets
   ```

5. Cancel the operation and try again with increased timeouts:
   ```hcl
   resource "aws_eks_cluster" "example" {
     # ...
     timeouts {
       create = "60m"
       update = "60m"
       delete = "30m"
     }
   }
   ```

### Error: "Invalid Kubernetes Version"

**Symptoms:**
- Error message about unsupported Kubernetes version
- Terraform plan fails with validation error

**Causes:**
- Specified Kubernetes version is no longer supported
- Invalid version format
- Region doesn't support the specified version

**Solution:**

1. List supported Kubernetes versions:
   ```bash
   aws eks describe-addon-versions --kubernetes-version 1.28
   ```

2. Use correct version format:
   ```hcl
   # Correct format
   kubernetes_version = "1.28"
   
   # Incorrect formats
   kubernetes_version = "v1.28"
   kubernetes_version = "1.28.0"
   ```

3. Update the variable to a supported version:
   ```hcl
   variable "default_kubernetes_version" {
     type        = string
     description = "Default Kubernetes version for EKS clusters"
     default     = "1.28"
   }
   ```

---

## EKS Addons Deployment Issues

### Error: "OIDC provider not found"

**Symptoms:**
- Error about missing OIDC provider
- IAM role creation fails for service accounts
- Addon deployment fails with permission errors

**Causes:**
- OIDC provider wasn't created with the EKS cluster
- Incorrect OIDC provider ARN or URL
- IAM permission issues

**Solution:**

1. Verify OIDC provider exists:
   ```bash
   aws iam list-open-id-connect-providers
   ```

2. If missing, create the OIDC provider:
   ```bash
   eksctl utils associate-iam-oidc-provider --cluster your-cluster-name --approve
   ```

3. Get the correct OIDC provider information:
   ```bash
   aws eks describe-cluster --name your-cluster-name --query "cluster.identity.oidc"
   ```

4. Update your configuration with the correct values:
   ```hcl
   # For each cluster configuration
   clusters = {
     "primary" = {
       # ...
       oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.region.amazonaws.com/id/EXAMPLED539D4633E53DE1B716D3041E"
       oidc_provider_url = "https://oidc.eks.region.amazonaws.com/id/EXAMPLED539D4633E53DE1B716D3041E"
     }
   }
   ```

### Error: "Cert Manager LetsEncrypt validation failed"

**Symptoms:**
- Cert-manager issuers show "Failed" status
- Certificate resources stuck in "pending" state
- Error about invalid LetsEncrypt configuration

**Causes:**
- Invalid email address for LetsEncrypt
- DNS validation problems
- IAM permission issues for Route53

**Solution:**

1. Check certificate and issuer status:
   ```bash
   kubectl get clusterissuer
   kubectl describe clusterissuer letsencrypt-prod
   kubectl get certificate -A
   kubectl describe certificate -n istio-system
   ```

2. Verify email address format:
   ```hcl
   # Correct format
   cert_manager_letsencrypt_email = "user@example.com"
   
   # Incorrect formats
   cert_manager_letsencrypt_email = "user@"
   cert_manager_letsencrypt_email = "user@example"
   ```

3. Check IAM permissions for Route53:
   ```bash
   # Service account should have these permissions
   aws iam simulate-principal-policy --policy-source-arn SERVICE_ACCOUNT_ROLE_ARN --action-names route53:GetChange route53:ChangeResourceRecordSets route53:ListResourceRecordSets
   ```

4. Validate DNS record creation:
   ```bash
   kubectl logs -n cert-manager -l app=cert-manager -c cert-manager
   ```

5. For stubborn issues, recreate the issuer:
   ```bash
   kubectl delete clusterissuer letsencrypt-prod
   # Wait for Terraform to recreate it, or recreate manually
   ```

---

## IAM and Permission Issues

### Error: "Access Denied for IAM role"

**Symptoms:**
- "Access Denied" errors in pod logs
- AWS service integrations failing
- Error message about missing IAM permissions

**Causes:**
- Incorrect IAM policy
- OIDC trust relationship issues
- Service account annotation missing

**Solution:**

1. Check service account annotation:
   ```bash
   kubectl get serviceaccount -n your-namespace your-sa -o yaml
   ```
   
   The annotation should look like:
   ```yaml
   annotations:
     eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/your-iam-role
   ```

2. Verify IAM role trust relationship:
   ```bash
   aws iam get-role --role-name your-iam-role --query 'Role.AssumeRolePolicyDocument'
   ```
   
   Trust policy should include:
   ```json
   {
     "Effect": "Allow",
     "Principal": {
       "Federated": "arn:aws:iam::123456789012:oidc-provider/oidc.eks.region.amazonaws.com/id/EXAMPLED539D4633E53DE1B716D3041E"
     },
     "Action": "sts:AssumeRoleWithWebIdentity",
     "Condition": {
       "StringEquals": {
         "oidc.eks.region.amazonaws.com/id/EXAMPLED539D4633E53DE1B716D3041E:sub": "system:serviceaccount:namespace:serviceaccount-name"
       }
     }
   }
   ```

3. Test the IAM policy:
   ```bash
   aws iam simulate-principal-policy --policy-source-arn ROLE_ARN --action-names s3:GetObject dynamodb:PutItem
   ```

4. Add required permissions to the policy:
   ```hcl
   # Update the policy document with missing permissions
   service_account_policy = jsonencode({
     Version = "2012-10-17"
     Statement = [
       {
         Effect   = "Allow"
         Action   = ["s3:GetObject", "s3:PutObject"]
         Resource = "arn:aws:s3:::your-bucket/*"
       }
     ]
   })
   ```

5. Force recreation of the service account:
   ```bash
   kubectl delete serviceaccount -n your-namespace your-sa
   # Wait for Terraform to recreate it
   ```

---

## Networking and Connectivity Issues

### Error: "Service not accessible"

**Symptoms:**
- Cannot reach services from outside the cluster
- LoadBalancer services stuck in "pending" state
- Istio gateway not routing traffic

**Causes:**
- Security group issues
- Network ACL restrictions
- Subnet configuration problems
- Load balancer controller issues

**Solution:**

1. Check service status:
   ```bash
   kubectl get svc -A
   ```

2. For LoadBalancer services, check if load balancer was created:
   ```bash
   # Get load balancer name
   LB_NAME=$(kubectl get svc -n your-namespace your-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
   
   # Check load balancer details
   aws elbv2 describe-load-balancers --names $LB_NAME
   ```

3. Verify security group allows traffic:
   ```bash
   # Get security group ID
   SG_ID=$(aws elbv2 describe-load-balancers --names $LB_NAME --query 'LoadBalancers[0].SecurityGroups[0]' --output text)
   
   # Check security group rules
   aws ec2 describe-security-groups --group-ids $SG_ID
   ```

4. Check AWS Load Balancer Controller logs:
   ```bash
   kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
   ```

5. For Istio gateway issues, check gateway status:
   ```bash
   kubectl get gateway -A
   kubectl describe gateway -n istio-system
   ```

6. Verify subnet tags for load balancer discovery:
   ```bash
   # Public subnets for internet-facing load balancers
   aws ec2 describe-subnets --filters "Name=tag:kubernetes.io/role/elb,Values=1"
   
   # Private subnets for internal load balancers
   aws ec2 describe-subnets --filters "Name=tag:kubernetes.io/role/internal-elb,Values=1"
   ```

---

## Terraform State Management

### Error: "Error locking state"

**Symptoms:**
- "Error acquiring the state lock" message
- Multiple users cannot run Terraform concurrently
- Terraform operations hanging

**Causes:**
- DynamoDB table issues
- Stale lock
- IAM permissions

**Solution:**

1. Check if a lock exists:
   ```bash
   aws dynamodb get-item --table-name terraform-locks --key '{"LockID":{"S":"your-lock-id"}}'
   ```

2. Force release the lock (use with caution):
   ```bash
   terraform force-unlock LOCK_ID
   ```

3. Verify DynamoDB table exists and is accessible:
   ```bash
   aws dynamodb describe-table --table-name terraform-locks
   ```

4. Check IAM permissions:
   ```bash
   aws iam simulate-principal-policy --policy-source-arn YOUR_IAM_ROLE_ARN --action-names dynamodb:GetItem dynamodb:PutItem dynamodb:DeleteItem
   ```

5. If needed, recreate the DynamoDB table:
   ```bash
   aws dynamodb create-table \
     --table-name terraform-locks \
     --attribute-definitions AttributeName=LockID,AttributeType=S \
     --key-schema AttributeName=LockID,KeyType=HASH \
     --billing-mode PAY_PER_REQUEST
   ```

### Error: "Error loading state"

**Symptoms:**
- "Error loading state" or "Failed to get existing workspaces" message
- Cannot access remote state

**Causes:**
- S3 bucket issues
- IAM permissions
- Backend configuration problems

**Solution:**

1. Check if the S3 bucket exists:
   ```bash
   aws s3 ls s3://your-terraform-state-bucket
   ```

2. Verify state file exists:
   ```bash
   aws s3 ls s3://your-terraform-state-bucket/path/to/terraform.tfstate
   ```

3. Test IAM permissions:
   ```bash
   aws iam simulate-principal-policy --policy-source-arn YOUR_IAM_ROLE_ARN --action-names s3:GetObject s3:PutObject s3:ListBucket
   ```

4. Verify backend configuration:
   ```hcl
   # Should match exactly
   terraform {
     backend "s3" {
       bucket         = "your-terraform-state-bucket"
       key            = "path/to/terraform.tfstate"
       region         = "us-west-2"
       encrypt        = true
       dynamodb_table = "terraform-locks"
     }
   }
   ```

5. If needed, re-initialize Terraform:
   ```bash
   terraform init -reconfigure
   ```

---

## Atmos Component Configuration

### Error: "Component values not propagating"

**Symptoms:**
- Terraform variables not getting expected values from Atmos
- `atmos terraform plan` shows unexpected variable values
- "Variable not defined" errors

**Causes:**
- YAML syntax issues
- Wrong variable paths
- Component inheritance problems

**Solution:**

1. Check YAML syntax:
   ```bash
   atmos workflow validate
   ```

2. Verify component configuration:
   ```bash
   atmos describe component component-name -s tenant-account-environment
   ```

3. Inspect variable values:
   ```bash
   atmos describe stack tenant-account-environment
   ```

4. Check for variable precedence issues:
   ```
   Variables are applied in this order:
   1. Base component defaults
   2. Stack defaults (globals)
   3. Environment configs
   4. Component overrides
   ```

5. Use deep merge for complex objects:
   ```yaml
   # Enable deep merge for object variables
   component:
     terraform:
       vars:
         my_map:
           __stack_lists_deep_merge_enabled: true
   ```

### Error: "Workflow execution failed"

**Symptoms:**
- `atmos workflow xyz` fails
- Error message about command execution
- Unexpected workflow behavior

**Causes:**
- Misconfigured workflow
- Missing environment variables
- Command syntax issues

**Solution:**

1. Check workflow definition:
   ```bash
   cat workflows/your-workflow.yaml
   ```

2. Verify command syntax:
   ```yaml
   steps:
     - command: atmos terraform plan component -s tenant-account-environment
       # Check for correct syntax here
   ```

3. Set required environment variables:
   ```bash
   export ATMOS_COMPONENT=component-name
   export ATMOS_STACK=tenant-account-environment
   ```

4. Run workflow with verbose logging:
   ```bash
   atmos workflow your-workflow --verbose
   ```

5. For issues with specific components, try running the component directly:
   ```bash
   atmos terraform plan component-name -s tenant-account-environment
   ```

---

## Need More Help?

For issues not covered in this guide:

1. Check CloudTrail for AWS API errors:
   ```bash
   aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=CreateCluster
   ```

2. Review CloudWatch Logs:
   ```bash
   aws logs describe-log-groups --log-group-name-prefix /aws/eks
   aws logs get-log-events --log-group-name /aws/eks/your-cluster --log-stream-name your-stream
   ```

3. Open an internal ticket with the DevOps team
4. Reference architecture documentation in the `/docs` directory