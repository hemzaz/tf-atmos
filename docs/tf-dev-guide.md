# Developing Terraform Components for Atmos: A Comprehensive Guide for Advanced Users

## Introduction

This guide is designed for experienced DevOps engineers and infrastructure developers who are looking to leverage Atmos to its full potential. We'll dive deep into the intricacies of developing Terraform components that are optimized for use with Atmos, covering advanced techniques, best practices, and common pitfalls.

## Component Structure

In Atmos, a Terraform component typically consists of the following files:

```
components/terraform/my-component/
├── main.tf
├── variables.tf
├── outputs.tf
├── providers.tf
├── data.tf
├── locals.tf
├── iam.tf
├── policies/
│   └── custom-policy.json
└── README.md
```

Let's break down each file's purpose and provide examples of advanced usage.

### 1. main.tf

This is where your primary resource definitions reside. When developing for Atmos, consider the following:

- Use `locals` for complex computations
- Leverage `dynamic` blocks for repetitive nested blocks
- Utilize `depends_on` for managing complex dependencies

Example:

```hcl
resource "aws_ecs_service" "this" {
  name            = local.service_name
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count

  network_configuration {
    subnets         = var.subnet_ids
    security_groups = [aws_security_group.this.id]
  }

  dynamic "load_balancer" {
    for_each = var.target_group_arn != null ? [1] : []
    content {
      target_group_arn = var.target_group_arn
      container_name   = local.container_name
      container_port   = var.container_port
    }
  }

  depends_on = [aws_iam_role_policy_attachment.ecs_task_execution_role_policy]
}
```

### 2. variables.tf

Define your input variables here. For Atmos compatibility:

- Use descriptive names and include detailed descriptions
- Provide sensible defaults where applicable
- Use validation blocks for complex type checking

Example:

```hcl
variable "vpc_cidr" {
  type        = string
  description = "The CIDR block for the VPC"
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "Must be a valid IPv4 CIDR block address."
  }
}

variable "subnet_configuration" {
  type = list(object({
    name                    = string
    cidr_block              = string
    availability_zone       = string
    map_public_ip_on_launch = bool
  }))
  description = "List of subnet configurations"
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to add to all resources"
  default     = {}
}
```

### 3. outputs.tf

Define outputs that might be useful for other components or for display. In Atmos:

- Output resource IDs and ARNs for cross-component references
- Use `sensitive = true` for outputs containing sensitive information
- Include descriptive documentation for each output

Example:

```hcl
output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.this.id
}

output "private_subnet_ids" {
  description = "List of IDs of private subnets"
  value       = aws_subnet.private[*].id
}

output "database_password" {
  description = "The password for the database"
  value       = aws_db_instance.this.password
  sensitive   = true
}
```

### 4. providers.tf

Define provider configurations here. For Atmos:

- Use variables for region and assume role configurations
- Consider using provider aliases for multi-region resources

Example:

```hcl
provider "aws" {
  region = var.region

  assume_role {
    role_arn = var.assume_role_arn
  }

  default_tags {
    tags = var.default_tags
  }
}

provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"

  assume_role {
    role_arn = var.assume_role_arn
  }
}
```

### 5. data.tf

Use this file for data source definitions. In Atmos:

- Fetch existing resource details to avoid hardcoding
- Use data sources for cross-account or cross-region resource lookups

Example:

```hcl
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_vpc" "selected" {
  count = var.vpc_id != null ? 1 : 0
  id    = var.vpc_id
}

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}
```

## New Infrastructure Components

In addition to the basic component structure, the productized version of this infrastructure includes several new components:

### 1. ECS Module

The ECS module provides container orchestration capabilities with support for both EC2 and Fargate launch types.

Key features:
- Cluster creation with container insights
- Capacity provider management
- Integration with auto-scaling groups
- Fargate profiles for serverless containers

### 2. RDS Module

The RDS module manages relational databases with:
- Subnet group and security group creation
- Parameter group customization
- Automated backups and snapshots
- Encryption and performance insights
- Secrets Manager integration for credentials

### 3. Lambda Module

The serverless Lambda module includes:
- Function deployment with multiple source options (S3, local)
- IAM role and policy management
- CloudWatch log group integration
- VPC connectivity options
- Event source mappings (API Gateway, S3, CloudWatch Events, SNS)
- Alias and version management

### 4. Monitoring Module

A comprehensive monitoring solution with:
- CloudWatch dashboards for environment-wide visibility
- Metric alarms for CPU, memory, and database connections
- Log groups with retention policies
- SNS topics for alarm notifications
- Custom metric filters for log analysis

## Advanced Techniques

### 1. Dynamic Resource Creation

Use `count` or `for_each` for creating multiple similar resources:

```hcl
resource "aws_subnet" "this" {
  for_each = { for subnet in var.subnet_configuration : subnet.name => subnet }

  vpc_id                  = local.vpc_id
  cidr_block              = each.value.cidr_block
  availability_zone       = each.value.availability_zone
  map_public_ip_on_launch = each.value.map_public_ip_on_launch

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${each.key}-subnet"
  })
}
```

### 2. Conditional Resource Creation

Use the `count` parameter for conditional resource creation:

```hcl
resource "aws_nat_gateway" "this" {
  count         = var.create_nat_gateway ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-nat-gateway"
  })
}
```

### 3. Complex Validations

Use lifecycle preconditions for complex validations:

```hcl
resource "aws_subnet" "private" {
  count             = length(var.private_subnets)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(var.tags, {
    Name = "${var.tags["Environment"]}-private-subnet-${count.index + 1}"
  })

  lifecycle {
    precondition {
      condition     = cidrsubnet(var.vpc_cidr, 8, count.index) == var.private_subnets[count.index]
      error_message = "Subnet CIDR ${var.private_subnets[count.index]} is not within the VPC CIDR ${var.vpc_cidr}"
    }
  }
}
```

### 4. Using `templatefile` Function

Leverage the `templatefile` function for complex configurations:

```hcl
resource "aws_ecs_task_definition" "this" {
  family                   = local.task_family
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = templatefile("${path.module}/task-definition.json.tpl", {
    container_name = local.container_name
    image          = var.container_image
    cpu            = var.task_cpu
    memory         = var.task_memory
    log_group      = aws_cloudwatch_log_group.this.name
    region         = data.aws_region.current.name
  })
}
```

## Best Practices for Atmos Components

1. **Complete Outputs**: Always provide comprehensive outputs for each component to enable cross-component references.

2. **Error Handling**: Implement proper error handling using lifecycle blocks, validations, and preconditions.

3. **Security Best Practices**: Follow security best practices for all components:
   - Encrypt sensitive data at rest and in transit
   - Use Secrets Manager for credentials
   - Implement least privilege IAM policies
   - Enable VPC isolation where appropriate

4. **Resource Naming**: Use consistent naming conventions that include environment, component, and purpose.

5. **Tagging Strategy**: Implement a comprehensive tagging strategy for cost allocation and resource management.

6. **State Management**: Design components with Atmos's centralized state management in mind, using appropriate backend configurations.

7. **Documentation**: Provide detailed README files for each component with usage examples and variable descriptions.

8. **Module Versioning**: Use semantic versioning for modules to ensure compatibility across environments.

9. **Conditional Features**: Use feature flags (boolean variables) to enable or disable certain features of a component.

10. **Cross-Account Support**: Design components to work across multiple AWS accounts using assume role functionality.

## Conclusion

Developing Terraform components for Atmos requires a deep understanding of both Terraform and Atmos. By following these advanced techniques and best practices, you can create highly modular, reusable, and maintainable infrastructure components that leverage the full power of Atmos for your multi-account, multi-environment AWS setups.

Remember, the key to successful Atmos component development is to think in terms of reusability, flexibility, and consistency across your entire infrastructure. Happy coding!