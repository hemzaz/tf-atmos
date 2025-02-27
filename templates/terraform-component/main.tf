# Template: Terraform Component Main File
# This template follows the best practices outlined in CLAUDE.md
# Replace placeholder values and comments with your actual implementation

locals {
  enabled = var.enabled

  # Standard name prefix for resources
  name_prefix = "${var.tags["Environment"]}-${var.name}"
  
  # Standard tags
  default_tags = {
    Name = local.name_prefix
    Component = "ComponentName" # Replace with your component name
    ManagedBy = "Terraform"
  }
  
  tags = merge(var.tags, local.default_tags)
}

# PRIMARY RESOURCES
# Replace this section with your component's primary resources

resource "aws_example_resource" "example" {
  count = local.enabled ? 1 : 0
  
  name        = local.name_prefix
  description = var.description
  
  # Other resource configuration...
  
  lifecycle {
    precondition {
      condition     = length(var.name) > 0 && length(var.name) <= 64
      error_message = "The name must be between 1 and 64 characters in length."
    }
  }
  
  tags = local.tags
}

# ASSOCIATED RESOURCES
# Replace this section with your component's associated resources

resource "aws_example_associated_resource" "example" {
  count = local.enabled ? 1 : 0
  
  primary_resource_id = aws_example_resource.example[0].id
  
  # Other resource configuration...
  
  tags = local.tags
}

# MONITORING & LOGGING
# Replace this section with monitoring and logging resources if applicable

resource "aws_cloudwatch_log_group" "logs" {
  count = local.enabled && var.enable_logging ? 1 : 0
  
  name              = "/aws/example/${local.name_prefix}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_id
  
  tags = local.tags
}

# SECURITY RESOURCES
# Replace this section with security-related resources if applicable

resource "aws_iam_role" "service_role" {
  count = local.enabled ? 1 : 0
  
  name = "${local.name_prefix}-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "example.amazonaws.com"
      }
    }]
  })
  
  tags = local.tags
}