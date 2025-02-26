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

### 6. locals.tf

Define local variables for complex computations or to improve readability. In Atmos:

- Use locals to construct resource names consistently
- Perform data transformations here to keep `main.tf` clean

Example:

```hcl
locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name

  name_prefix = "${var.namespace}-${var.environment}-${var.name}"

  vpc_id = var.vpc_id != null ? var.vpc_id : data.aws_vpc.selected[0].id

  subnet_ids = flatten([
    for subnet in var.subnet_configuration : [
      aws_subnet.this[subnet.name].id
    ]
  ])

  common_tags = merge(
    var.tags,
    {
      "Namespace"   = var.namespace
      "Environment" = var.environment
    }
  )
}
```

### 7. iam.tf

Define IAM roles and policies here. For Atmos:

- Use separate files for complex IAM configurations
- Leverage `data` sources for managed policies
- Use policy documents for custom policies

Example:

```hcl
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${local.name_prefix}-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "secrets_access" {
  name = "${local.name_prefix}-secrets-access-policy"
  role = aws_iam_role.ecs_task_execution_role.id

  policy = file("${path.module}/policies/secrets-access-policy.json")
}
```

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

Use `terraform_data` (formerly `null_resource`) for complex validations:

```hcl
resource "terraform_data" "validate_cidr_blocks" {
  count = length(var.subnet_configuration)

  lifecycle {
    precondition {
      condition     = cidrsubnet(var.vpc_cidr, 8, count.index) == var.subnet_configuration[count.index].cidr_block
      error_message = "Subnet CIDR ${var.subnet_configuration[count.index].cidr_block} is not within the VPC CIDR ${var.vpc_cidr}"
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

1. **Modularity**: Design components to be as modular as possible, allowing for easy composition in Atmos stacks.

2. **Consistent Naming**: Use consistent naming conventions across all components. Leverage Atmos's `${tenant}`, `${environment}`, and `${stage}` variables.

3. **Default Tags**: Always include default tags that can be overridden or extended in Atmos stack configurations.

4. **Use Atmos Variables**: Leverage Atmos's built-in variables in your component configurations.

5. **Documentation**: Provide comprehensive README files for each component, detailing usage, inputs, and outputs.

6. **Testing**: Implement automated tests for your components using tools like Terratest.

7. **Version Constraints**: Use version constraints for providers and modules to ensure consistency across environments.

8. **State Management**: Design components with Atmos's centralized state management in mind.

## Conclusion

Developing Terraform components for Atmos requires a deep understanding of both Terraform and Atmos. By following these advanced techniques and best practices, you can create highly modular, reusable, and maintainable infrastructure components that leverage the full power of Atmos for your multi-account, multi-environment AWS setups.

Remember, the key to successful Atmos component development is to think in terms of reusability, flexibility, and consistency across your entire infrastructure. Happy coding!