provider "aws" {
  region = "us-west-2"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "4.0.0"

  name = "example-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-west-2a", "us-west-2b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = {
    Environment = "example"
    Project     = "EC2-Example"
    ManagedBy   = "Terraform"
  }
}

module "ec2_instances" {
  source = "../../components/terraform/ec2"

  region     = "us-west-2"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets

  # Enable SSH key generation and storage
  create_ssh_keys                   = true
  store_ssh_keys_in_secrets_manager = true
  ssh_key_algorithm                 = "RSA"
  ssh_key_rsa_bits                  = 4096

  # Create a global key for all instances that don't specify their own key
  global_key_name = "example-global-key"

  # Define instances
  # For existing keys, you would specify this
  # default_key_name = "my-existing-key-pair" # Uncomment to use an existing default key

  instances = {
    # Public bastion host
    bastion = {
      instance_type = "t3.micro"
      subnet_id     = module.vpc.public_subnets[0]
      # Key will be auto-generated using global key

      # Security group configuration
      allowed_ingress_rules = [
        {
          from_port   = 22
          to_port     = 22
          protocol    = "tcp"
          cidr_blocks = ["192.168.1.0/24"] # Replace with your IP or VPN CIDR
          description = "SSH access from trusted network"
        }
      ]

      allowed_egress_rules = [
        {
          from_port   = 443
          to_port     = 443
          protocol    = "tcp"
          cidr_blocks = ["0.0.0.0/0"]
          description = "HTTPS outbound"
        },
        {
          from_port   = 80
          to_port     = 80
          protocol    = "tcp"
          cidr_blocks = ["0.0.0.0/0"]
          description = "HTTP outbound"
        }
      ]

      # Instance config
      root_volume_size = 20
      root_volume_type = "gp3"

      # Additional tags
      tags = {
        Role = "Bastion"
        Name = "example-bastion"
      }
    },

    # Private application server 
    app_server = {
      instance_type = "t3.small"
      subnet_id     = module.vpc.private_subnets[0]
      # Generate a specific key for this instance instead of using global
      key_name = null # Force creation of an individual key

      # Security group configuration
      allowed_ingress_rules = [
        {
          from_port   = 8080
          to_port     = 8080
          protocol    = "tcp"
          cidr_blocks = [module.vpc.vpc_cidr_block]
          description = "Application access from VPC"
        }
      ]

      # Add custom IAM policy for S3 access
      custom_iam_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
          {
            Action = [
              "s3:GetObject",
              "s3:ListBucket"
            ]
            Effect   = "Allow"
            Resource = ["arn:aws:s3:::example-app-bucket", "arn:aws:s3:::example-app-bucket/*"]
          }
        ]
      })

      # Instance config
      root_volume_size = 50

      # Additional tags
      tags = {
        Role = "Application"
        Name = "example-app-server"
      }
    },

    # Database server with existing key pair
    db_server = {
      instance_type = "t3.medium"
      subnet_id     = module.vpc.private_subnets[1]
      # Use an existing key pair (if this key doesn't exist, deployment will fail)
      key_name = "existing-key-pair-name" # Replace with an actual existing key name

      # Security group configuration
      allowed_ingress_rules = [
        {
          from_port   = 5432
          to_port     = 5432
          protocol    = "tcp"
          cidr_blocks = [module.vpc.vpc_cidr_block]
          description = "PostgreSQL access from VPC"
        }
      ]

      # Instance config
      root_volume_size = 100

      # Additional tags
      tags = {
        Role = "Database"
        Name = "example-db-server"
      }
    }
  }

  tags = {
    Environment = "example"
    Project     = "EC2-Example"
    ManagedBy   = "Terraform"
  }
}

output "bastion_public_ip" {
  value       = module.ec2_instances.instance_public_ips["bastion"]
  description = "Public IP of the bastion host"
}

output "instance_ids" {
  value       = module.ec2_instances.instance_ids
  description = "Map of instance names to instance IDs"
}

output "ssh_key_secret_arns" {
  value       = module.ec2_instances.ssh_key_secret_arns
  description = "ARNs of secrets containing SSH private keys"
  sensitive   = true
}

output "generated_key_names" {
  value       = module.ec2_instances.generated_key_names
  description = "Names of the generated SSH key pairs"
}

output "global_key_name" {
  value       = module.ec2_instances.global_key_name
  description = "Name of the global SSH key if created"
}

output "global_key_secret_arn" {
  value       = module.ec2_instances.global_key_secret_arn
  description = "ARN of the Secret Manager secret containing the global SSH key"
  sensitive   = true
}

output "instances_using_global_key" {
  value       = module.ec2_instances.instances_using_global_key
  description = "List of instance names using the global SSH key"
}

output "instances_using_individual_keys" {
  value       = module.ec2_instances.instances_using_individual_keys
  description = "List of instance names using individual SSH keys"
}