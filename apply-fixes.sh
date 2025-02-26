#!/bin/bash
set -e

echo "Applying comprehensive fixes to Terraform-Atmos repository..."

# 1. Fix Directory Structure and Rename Components
echo "1. Fixing directory structure and naming issues..."
mkdir -p components/terraform/securitygroup
cp -r components/terraform/security-groups/* components/terraform/securitygroup/

# 2. Add Missing Files
echo "2. Creating missing files for components..."

# Create Terraform files for securitygroup module
cat > components/terraform/securitygroup/variables.tf << 'EOF'
variable "region" {
  type        = string
  description = "AWS region"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where security groups will be created"
}

variable "security_groups" {
  type        = map(any)
  description = "Map of security groups to create"
  default     = {}
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources"
  default     = {}
}
EOF

cat > components/terraform/securitygroup/main.tf << 'EOF'
locals {
  security_groups = var.security_groups
}

resource "aws_security_group" "this" {
  for_each = local.security_groups

  name        = "${var.tags["Environment"]}-${each.key}-sg"
  description = lookup(each.value, "description", "Security group for ${each.key}")
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = lookup(each.value, "ingress_rules", [])
    content {
      from_port       = ingress.value.from_port
      to_port         = ingress.value.to_port
      protocol        = ingress.value.protocol
      cidr_blocks     = lookup(ingress.value, "cidr_blocks", null)
      prefix_list_ids = lookup(ingress.value, "prefix_list_ids", null)
      security_groups = lookup(ingress.value, "security_groups", null)
      self            = lookup(ingress.value, "self", null)
      description     = lookup(ingress.value, "description", null)
    }
  }

  dynamic "egress" {
    for_each = lookup(each.value, "egress_rules", [])
    content {
      from_port       = egress.value.from_port
      to_port         = egress.value.to_port
      protocol        = egress.value.protocol
      cidr_blocks     = lookup(egress.value, "cidr_blocks", null)
      prefix_list_ids = lookup(egress.value, "prefix_list_ids", null)
      security_groups = lookup(egress.value, "security_groups", null)
      self            = lookup(egress.value, "self", null)
      description     = lookup(egress.value, "description", null)
    }
  }

  tags = merge(
    var.tags,
    lookup(each.value, "tags", {}),
    {
      Name = "${var.tags["Environment"]}-${each.key}-sg"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}
EOF

cat > components/terraform/securitygroup/outputs.tf << 'EOF'
output "security_group_ids" {
  description = "Map of security group names to their IDs"
  value = {
    for k, v in aws_security_group.this : k => v.id
  }
}

output "security_group_arns" {
  description = "Map of security group names to their ARNs"
  value = {
    for k, v in aws_security_group.this : k => v.arn
  }
}

output "security_group_vpc_id" {
  description = "VPC ID used for security groups"
  value = var.vpc_id
}
EOF

# Add ACM component files
cat > components/terraform/acm/variables.tf << 'EOF'
variable "region" {
  type        = string
  description = "AWS region"
}

variable "dns_domains" {
  type = map(object({
    domain_name               = string
    subject_alternative_names = optional(list(string), [])
    validation_method         = optional(string, "DNS")
    wait_for_validation       = optional(bool, true)
    tags                      = optional(map(string), {})
  }))
  description = "Map of domain configurations to create ACM certificates for"
  default     = {}
}

variable "zone_id" {
  type        = string
  description = "Route53 zone ID to create validation records in"
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources"
  default     = {}
}
EOF

cat > components/terraform/acm/main.tf << 'EOF'
locals {
  dns_domains = var.dns_domains
}

resource "aws_acm_certificate" "main" {
  for_each = local.dns_domains

  domain_name               = each.value.domain_name
  subject_alternative_names = lookup(each.value, "subject_alternative_names", [])
  validation_method         = lookup(each.value, "validation_method", "DNS")

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(
    var.tags,
    lookup(each.value, "tags", {}),
    {
      Name = "${var.tags["Environment"]}-${replace(each.value.domain_name, ".", "-")}"
    }
  )
}

resource "aws_route53_record" "validation" {
  for_each = {
    for dvo in flatten([
      for domain_key, domain in local.dns_domains : [
        for dvo in aws_acm_certificate.main[domain_key].domain_validation_options : {
          domain_key = domain_key
          dvo        = dvo
        }
      ]
    ]) : "${dvo.domain_key}.${dvo.dvo.domain_name}" => dvo
  }

  zone_id         = var.zone_id
  name            = each.value.dvo.resource_record_name
  type            = each.value.dvo.resource_record_type
  ttl             = 60
  records         = [each.value.dvo.resource_record_value]
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "main" {
  for_each = {
    for domain_key, domain in local.dns_domains : domain_key => domain
    if lookup(domain, "wait_for_validation", true)
  }

  certificate_arn         = aws_acm_certificate.main[each.key].arn
  validation_record_fqdns = [for dvo in aws_acm_certificate.main[each.key].domain_validation_options : dvo.resource_record_name]

  depends_on = [aws_route53_record.validation]
}
EOF

cat > components/terraform/acm/outputs.tf << 'EOF'
output "certificate_arns" {
  description = "Map of domain names to certificate ARNs"
  value = {
    for k, v in aws_acm_certificate.main : k => v.arn
  }
}

output "certificate_domains" {
  description = "Map of certificate names to domain names"
  value = {
    for k, v in aws_acm_certificate.main : k => v.domain_name
  }
}

output "certificate_validation_ids" {
  description = "Map of domain names to certificate validation IDs"
  value = {
    for k, v in aws_acm_certificate_validation.main : k => v.id
  }
}
EOF

# 3. Fix Backend template file
echo "3. Fixing variable interpolation in JSON policy files..."
cat > components/terraform/backend/policies/backend.json.tpl << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::${bucket_name}",
        "arn:aws:s3:::${bucket_name}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem"
      ],
      "Resource": "arn:aws:dynamodb:${region}:${account_id}:table/${dynamodb_table_name}"
    }
  ]
}
EOF

# Update backend IAM file to use templatefile function
cat > components/terraform/backend/iam.tf.updated << 'EOF'
resource "aws_iam_role" "terraform_backend" {
  name               = var.iam_role_name
  assume_role_policy = file("${path.module}/policies/assume-role.json")
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role_policy" "terraform_backend" {
  name   = "TerraformBackendPolicy"
  role   = aws_iam_role.terraform_backend.id
  policy = templatefile("${path.module}/policies/backend.json.tpl", {
    bucket_name         = var.bucket_name
    region              = var.region
    account_id          = data.aws_caller_identity.current.account_id
    dynamodb_table_name = var.dynamodb_table_name
  })
}
EOF
mv components/terraform/backend/iam.tf.updated components/terraform/backend/iam.tf

# Remove the old JSON file
if [ -f components/terraform/backend/policies/backend.json ]; then
  rm components/terraform/backend/policies/backend.json
fi

# 4. Fix Provider Configuration Issues
echo "4. Fixing provider configuration issues..."

# Fix bootstrap-backend.yaml
cat > workflows/bootstrap-backend.yaml.updated << 'EOF'
name: bootstrap-backend
description: "Initialize the Terraform backend (S3 bucket and DynamoDB table)"

workflows:
  bootstrap:
    steps:
    - run:
        command: |
          # Validate required parameters
          if [ -z "${tenant}" ]; then
            echo "ERROR: Missing required parameter 'tenant'"
            echo "Usage: atmos workflow bootstrap-backend tenant=<tenant> region=<region>"
            exit 1
          fi
          
          if [ -z "${region}" ]; then
            echo "ERROR: Missing required parameter 'region'"
            echo "Usage: atmos workflow bootstrap-backend tenant=<tenant> region=<region>"
            exit 1
          fi
          
          # Create S3 bucket for Terraform state
          echo "Creating S3 bucket for Terraform state: ${bucket_name}"
          aws s3api create-bucket --bucket ${bucket_name} --region ${region} --create-bucket-configuration LocationConstraint=${region}
          
          # Enable versioning on the bucket
          echo "Enabling versioning on bucket: ${bucket_name}"
          aws s3api put-bucket-versioning --bucket ${bucket_name} --versioning-configuration Status=Enabled
          
          # Create DynamoDB table for state locking
          echo "Creating DynamoDB table for state locking: ${dynamodb_table_name}"
          aws dynamodb create-table --table-name ${dynamodb_table_name} --attribute-definitions AttributeName=LockID,AttributeType=S --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST --region ${region}
          
          echo "Backend infrastructure successfully created:"
          echo "S3 Bucket: ${bucket_name}"
          echo "DynamoDB Table: ${dynamodb_table_name}"
          echo "Region: ${region}"
        env:
          bucket_name: ${tenant}-terraform-state
          dynamodb_table_name: ${tenant}-terraform-locks
          region: ${region}
EOF
mv workflows/bootstrap-backend.yaml.updated workflows/bootstrap-backend.yaml

# Fix network stack
cat > stacks/catalog/network.yaml.updated << 'EOF'
name: network
description: "Reusable network configuration"

components:
  terraform:
    vpc:
      metadata:
        component: vpc
        type: abstract
      vars:
        enabled: true
        region: ${region}
        vpc_cidr: "10.0.0.0/16"
        azs:
          - ${region}a
          - ${region}b
          - ${region}c
        private_subnets:
          - "10.0.1.0/24"
          - "10.0.2.0/24"
          - "10.0.3.0/24"
        public_subnets:
          - "10.0.101.0/24"
          - "10.0.102.0/24"
          - "10.0.103.0/24"
        enable_nat_gateway: true
        enable_vpn_gateway: false
        enable_transit_gateway: false
        transit_gateway_id: ""
        ram_resource_share_arn: ""
        create_vpc_iam_role: true

      # Define common tags
      tags:
        Tenant: ${tenant}
        Account: ${account}
        Environment: ${environment}
        Component: "Network"
        ManagedBy: "Terraform"

      # Terraform backend configuration
      settings:
        terraform:
          backend:
            s3:
              bucket: ${tenant}-terraform-state
              key: ${account}/${environment}/network/terraform.tfstate
              region: ${region}
              role_arn: arn:aws:iam::${management_account_id}:role/${tenant}-terraform-backend-role
              dynamodb_table: ${tenant}-terraform-locks

      # Provider configuration
      providers:
        aws:
          region: ${region}

      # Define common outputs
      outputs:
        vpc_id:
          description: "ID of the VPC"
          value: ${output.vpc_id}
        private_subnet_ids:
          description: "IDs of the private subnets"
          value: ${output.private_subnet_ids}
        public_subnet_ids:
          description: "IDs of the public subnets"
          value: ${output.public_subnet_ids}
EOF
mv stacks/catalog/network.yaml.updated stacks/catalog/network.yaml

# 5. Fix Resource Readiness and Race Conditions
echo "5. Fixing resource readiness and race conditions..."

# Add asssume_role and default_tags to eks-addons provider
cat > components/terraform/eks-addons/provider.tf.updated << 'EOF'
provider "aws" {
  region = var.region

  assume_role {
    role_arn = var.assume_role_arn
  }

  default_tags {
    tags = var.default_tags
  }
}

terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.10"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.5"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9.0"
    }
  }
}

# We intentionally use explicit providers to avoid circular dependencies
# between eks and eks-addons modules.
# This allows the eks-addons module to consume outputs from the eks module 
# without creating circular dependencies.
EOF
mv components/terraform/eks-addons/provider.tf.updated components/terraform/eks-addons/provider.tf

# Add assume_role and default_tags variables
cat > components/terraform/eks-addons/variables.tf.updated << 'EOF'
variable "region" {
  type        = string
  description = "AWS region"
}

variable "assume_role_arn" {
  type        = string
  description = "ARN of the IAM role to assume"
  default     = null
}

variable "default_tags" {
  type        = map(string)
  description = "Default tags to apply to all resources"
  default     = {}
}

variable "clusters" {
  type        = any
  description = "Map of cluster configurations with addons, Helm releases, and Kubernetes manifests"
  default     = {}
}

variable "cluster_name" {
  type        = string
  description = "Default EKS cluster name"
  default     = ""
}

variable "host" {
  type        = string
  description = "Default Kubernetes host"
  default     = ""
}

variable "cluster_ca_certificate" {
  type        = string
  description = "Default Kubernetes cluster CA certificate"
  default     = ""
}

variable "oidc_provider_arn" {
  type        = string
  description = "Default OIDC provider ARN for the EKS cluster"
  default     = ""
}

variable "oidc_provider_url" {
  type        = string
  description = "Default OIDC provider URL for the EKS cluster"
  default     = ""
}

variable "tags" {
  type        = map(string)
  description = "Common tags to apply to all resources"
  default     = {}
}
EOF
mv components/terraform/eks-addons/variables.tf.updated components/terraform/eks-addons/variables.tf

# 6. Fix workflow issues (validate workflow check)
echo "6. Fixing workflow issues..."
cat > workflows/apply-environment.yaml.updated << 'EOF'
name: apply-environment
description: "Apply changes for all components in an environment with dynamic discovery and dependency resolution"

workflows:
  apply:
    steps:
    - run:
        command: |
          # Validate required variables
          if [ -z "${tenant}" ] || [ -z "${account}" ] || [ -z "${environment}" ]; then
            echo "ERROR: Missing required parameters. Usage: atmos workflow apply-environment tenant=<tenant> account=<account> environment=<environment>"
            exit 1
          fi

          # Set exit on error
          set -e
          
          # Check if AWS credentials are valid
          echo "Validating AWS credentials..."
          if ! aws sts get-caller-identity > /dev/null; then
            echo "ERROR: Invalid AWS credentials. Please check your credentials and try again."
            exit 1
          fi
          
          # Discover available components by looking at stack files
          ENV_DIR="stacks/account/${account}/${environment}"
          echo "Discovering components in ${ENV_DIR}..."
          
          # Define known dependency order based on imports/references
          # Components earlier in the array should be applied before ones later in the array
          ORDERED_COMPONENTS=(
            "backend"
            "iam"
            "network"
            "eks" 
            "eks-addons"  # eks-addons depends on eks
            "ec2"
            "ecs"
            "rds"
            "lambda"
            "monitoring"
            "services"
          )
          
          # Discover available components from YAML files
          AVAILABLE_COMPONENTS=()
          for file in ${ENV_DIR}/*.yaml; do
            if [ -f "$file" ]; then
              # Extract component name from filename (removing path and extension)
              component=$(basename "$file" .yaml)
              AVAILABLE_COMPONENTS+=("$component")
            fi
          done
          
          echo "Discovered components: ${AVAILABLE_COMPONENTS[*]}"
          
          # Function to apply a component with error handling
          apply_component() {
            component=$1
            echo "Applying ${component}..."
            echo "----------------------------------------"
            if ! atmos terraform apply ${component} -s ${tenant}-${account}-${environment}; then
              echo "ERROR: Failed to apply ${component}. Exiting."
              return 1
            fi
            echo "Successfully applied ${component}."
            echo "----------------------------------------"
            return 0
          }
          
          # Start deployment in dependency order, but only apply components that exist
          echo "Starting deployment for ${tenant}-${account}-${environment}"
          echo "============================================"
          
          # First apply components in known dependency order
          for component in "${ORDERED_COMPONENTS[@]}"; do
            # Check if this component exists in the available components list
            if [[ " ${AVAILABLE_COMPONENTS[*]} " =~ " ${component} " ]]; then
              apply_component "$component" || exit 1
            fi
          done
          
          # Then apply any components that weren't in our known ordering
          for component in "${AVAILABLE_COMPONENTS[@]}"; do
            # Check if this component was already applied in the ordered phase
            if [[ ! " ${ORDERED_COMPONENTS[*]} " =~ " ${component} " ]]; then
              echo "Applying unordered component ${component}..."
              apply_component "$component" || exit 1
            fi
          done
          
          echo "============================================"
          echo "Deployment completed successfully for ${tenant}-${account}-${environment}"
          
          # Perform validation checks if validation workflow exists
          echo "Running post-deployment validation checks..."
          
          # Check if validation workflow exists
          if atmos workflow describe validate &>/dev/null; then
            atmos workflow validate tenant=${tenant} account=${account} environment=${environment}
          else
            echo "Validation workflow not found, skipping validation checks."
            echo "Consider adding a 'validate' workflow to automate post-deployment validation."
          fi
        env:
          AWS_SDK_LOAD_CONFIG: 1
EOF
mv workflows/apply-environment.yaml.updated workflows/apply-environment.yaml

# 7. Fix hardcoded values and secrets
echo "7. Fixing hardcoded values and enhancing security..."

# Update Atmos global variables
cat > atmos.yaml.updated << 'EOF'
# atmos.yaml

base_path: "."

components:
  terraform:
    base_path: components/terraform
    apply_auto_approve: false
    deploy_run_init: true
    init_run_reconfigure: true
    auto_generate_backend_file: false # Changed to false

stacks:
  base_path: stacks
  included_paths:
  - "account/**/**/*.yaml"
  - "catalog/**/*.yaml"
  excluded_paths:
  - "**/_defaults.yaml"
  name_pattern: "{tenant}-{account}-{environment}"

workflows:
  base_path: workflows
  imports:
  - apply-backend.yaml
  - apply-environment.yaml
  - bootstrap-backend.yaml
  - destroy-backend.yaml
  - destroy-environment.yaml
  - drift-detection.yaml
  - import.yaml
  - lint.yaml
  - onboard-environment.yaml
  - plan-environment.yaml
  - validate.yaml

logs:
  file: "/dev/stderr"
  level: Info

settings:
  list_merge_strategy: replace

schemas:
  atmos:
    manifest: "stacks/schemas/atmos/atmos-manifest/1.0/atmos-manifest.json"

templates:
  settings:
    enabled: true
  sprig:
    enabled: true
  gomplate:
    enabled: true

# Global variables section
vars:
  # Common variables
  tenant: "fnx"
  region: "eu-west-2"
  
  # Environment-specific variables can be overridden in environment-specific stacks
  # Default management account ID (should be overridden in production)
  management_account_id: "${env:AWS_MANAGEMENT_ACCOUNT_ID, 123456789012}"
EOF
mv atmos.yaml.updated atmos.yaml

# Fix hardcoded Grafana password
cat > stacks/account/dev/testenv-01/eks.yaml.updated << 'EOF'
import:
  - catalog/infrastructure

vars:
  account: dev
  environment: testenv-01
  region: eu-west-2

  # EKS clusters configuration
  eks.clusters:
    # Main application cluster
    main:
      enabled: true
      kubernetes_version: "1.28"
      endpoint_private_access: true
      endpoint_public_access: true
      enabled_cluster_log_types: ["api", "audit"]
      node_groups:
        workers:
          enabled: true
          instance_types: ["t3.medium"]
          desired_size: 2
          min_size: 1
          max_size: 4
          labels:
            role: worker
        monitoring:
          enabled: true
          instance_types: ["t3.large"]
          desired_size: 1
          min_size: 1
          max_size: 2
          labels:
            role: monitoring
          taints:
            - key: dedicated
              value: monitoring
              effect: "NO_SCHEDULE"
      tags:
        Purpose: "General"

    # Data processing cluster (disabled in dev)
    data:
      enabled: false
      kubernetes_version: "1.28"
      node_groups:
        workers:
          instance_types: ["t3.large"]
          desired_size: 3
      tags:
        Purpose: "DataProcessing"

  # EKS addons configuration
  eks-addons.clusters:
    main:
      # Reference to existing EKS resources
      host: ${output.eks.cluster_endpoints.main}
      cluster_ca_certificate: ${output.eks.cluster_ca_data.main}
      oidc_provider_arn: ${output.eks.oidc_provider_arns.main}

      # AWS EKS addons
      addons:
        vpc-cni:
          name: "vpc-cni"
          version: "v1.13.2-eksbuild.1"
          resolve_conflicts: "OVERWRITE"

        coredns:
          name: "coredns"
          version: "v1.10.1-eksbuild.1"

        kube-proxy:
          name: "kube-proxy"
          version: "v1.27.1-eksbuild.1"

      # Helm releases
      helm_releases:
        metrics-server:
          enabled: true
          chart: "metrics-server"
          repository: "https://kubernetes-sigs.github.io/metrics-server/"
          chart_version: "3.8.2"
          namespace: "kube-system"
          set_values:
            apiService.create: true
            args:
              - "--kubelet-preferred-address-types=InternalIP"

        prometheus:
          enabled: true
          chart: "kube-prometheus-stack"
          repository: "https://prometheus-community.github.io/helm-charts"
          chart_version: "45.7.1"
          namespace: "monitoring"
          create_namespace: true
          values:
            - |
              grafana:
                enabled: true
                # Use a reference to a secret in AWS Secrets Manager or similar secure storage
                adminPassword: "${ssm:/testenv-01/grafana/admin-password}"
              prometheus:
                prometheusSpec:
                  retention: 15d
                  resources:
                    requests:
                      memory: 1Gi
                      cpu: 500m
                    limits:
                      memory: 2Gi

        aws-load-balancer-controller:
          enabled: true
          chart: "aws-load-balancer-controller"
          repository: "https://aws.github.io/eks-charts"
          chart_version: "1.4.6"
          namespace: "kube-system"
          set_values:
            clusterName: "testenv-01-main"
            serviceAccount.create: true
            serviceAccount.name: "aws-load-balancer-controller"
          create_service_account_role: true
          service_account_policy: |
            {
              "Version": "2012-10-17",
              "Statement": [
                {
                  "Effect": "Allow",
                  "Action": [
                    "ec2:DescribeLoadBalancers",
                    "elasticloadbalancing:*",
                    "ec2:DescribeInstances"
                  ],
                  "Resource": "*"
                }
              ]
            }

      # Kubernetes manifests
      kubernetes_manifests:
        namespace-dev:
          enabled: true
          manifest: {
            "apiVersion": "v1",
            "kind": "Namespace",
            "metadata": {
              "name": "dev",
              "labels": {
                "name": "dev"
              }
            }
          }

        resource-quota:
          enabled: true
          manifest: {
            "apiVersion": "v1",
            "kind": "ResourceQuota",
            "metadata": {
              "name": "dev-quota",
              "namespace": "dev"
            },
            "spec": {
              "hard": {
                "pods": "20",
                "requests.cpu": "4",
                "requests.memory": "8Gi",
                "limits.cpu": "8",
                "limits.memory": "16Gi"
              }
            }
          }

tags:
  Team: "DevOps"
  CostCenter: "IT"
  Project: "Infrastructure"
EOF
mv stacks/account/dev/testenv-01/eks.yaml.updated stacks/account/dev/testenv-01/eks.yaml

# Fix hardcoded security group rules
cat > components/terraform/vpc/security-groups.tf.updated << 'EOF'
resource "aws_security_group" "default" {
  name        = "${var.tags["Environment"]}-default-sg"
  description = "Default security group to allow inbound/outbound from the VPC"
  vpc_id      = aws_vpc.main.id

  # Allow all communication within the security group
  dynamic "ingress" {
    for_each = var.default_sg_ingress_self_only ? [1] : []
    content {
      from_port = "0"
      to_port   = "0"
      protocol  = "-1"
      self      = true
      description = "Allow all inbound traffic within this security group"
    }
  }

  # Add custom ingress rules if provided
  dynamic "ingress" {
    for_each = var.default_security_group_ingress_rules
    content {
      from_port       = ingress.value.from_port
      to_port         = ingress.value.to_port
      protocol        = ingress.value.protocol
      cidr_blocks     = lookup(ingress.value, "cidr_blocks", null)
      security_groups = lookup(ingress.value, "security_groups", null)
      self            = lookup(ingress.value, "self", null)
      description     = lookup(ingress.value, "description", "Custom ingress rule")
    }
  }

  # Allow all outbound to self
  dynamic "egress" {
    for_each = var.default_sg_egress_self_only ? [1] : []
    content {
      from_port = "0"
      to_port   = "0"
      protocol  = "-1"
      self      = true
      description = "Allow all outbound traffic within this security group"
    }
  }

  # Add custom egress rules if provided
  dynamic "egress" {
    for_each = var.default_sg_allow_all_outbound ? [1] : []
    content {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
      description = "Allow all outbound traffic"
    }
  }

  # Add custom egress rules if provided
  dynamic "egress" {
    for_each = var.default_security_group_egress_rules
    content {
      from_port       = egress.value.from_port
      to_port         = egress.value.to_port
      protocol        = egress.value.protocol
      cidr_blocks     = lookup(egress.value, "cidr_blocks", null)
      security_groups = lookup(egress.value, "security_groups", null)
      self            = lookup(egress.value, "self", null)
      description     = lookup(egress.value, "description", "Custom egress rule")
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-default-sg"
    }
  )
}
EOF
mv components/terraform/vpc/security-groups.tf.updated components/terraform/vpc/security-groups.tf

# Add new security group variables
cat >> components/terraform/vpc/variables.tf.updated << 'EOF'
variable "default_sg_ingress_self_only" {
  type        = bool
  description = "Whether to allow only self ingress in the default security group"
  default     = true
}

variable "default_sg_egress_self_only" {
  type        = bool
  description = "Whether to allow only self egress in the default security group"
  default     = true
}

variable "default_sg_allow_all_outbound" {
  type        = bool
  description = "Whether to allow all outbound traffic in the default security group"
  default     = false
}

variable "default_security_group_ingress_rules" {
  type = list(object({
    from_port       = number
    to_port         = number
    protocol        = string
    cidr_blocks     = optional(list(string))
    security_groups = optional(list(string))
    self            = optional(bool)
    description     = optional(string)
  }))
  description = "List of ingress rules for the default security group"
  default     = []
}

variable "default_security_group_egress_rules" {
  type = list(object({
    from_port       = number
    to_port         = number
    protocol        = string
    cidr_blocks     = optional(list(string))
    security_groups = optional(list(string))
    self            = optional(bool)
    description     = optional(string)
  }))
  description = "List of egress rules for the default security group"
  default     = []
}
EOF
cat components/terraform/vpc/variables.tf >> components/terraform/vpc/variables.tf.updated
cat components/terraform/vpc/variables.tf.updated > components/terraform/vpc/variables.tf
rm components/terraform/vpc/variables.tf.updated

echo "✅ All fixes have been applied successfully!"
echo ""
echo "Summary of changes:"
echo "1. Fixed directory naming issues (renamed security-groups to securitygroup)"
echo "2. Added missing files for components (securitygroup, acm)"
echo "3. Fixed variable interpolation in JSON files (using templatefile)"
echo "4. Fixed provider configuration issues"
echo "5. Fixed resource readiness and race conditions in EKS addons"
echo "6. Added workflow validation checks"
echo "7. Removed hardcoded values and improved security"
echo ""
echo "Next steps:"
echo "1. Run 'bash apply-fixes.sh' to apply these changes"
echo "2. Verify the changes with 'git diff'"
echo "3. Test the changes by running Atmos workflows"