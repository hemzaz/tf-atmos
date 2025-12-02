locals {
  name_prefix = var.name_prefix

  common_tags = merge(
    {
      Name        = local.name_prefix
      Environment = var.environment
      ManagedBy   = "Terraform"
      Module      = "vpc-endpoints"
    },
    var.tags
  )

  # Service name mapping
  service_names = {
    s3                   = "com.amazonaws.${data.aws_region.current.name}.s3"
    dynamodb             = "com.amazonaws.${data.aws_region.current.name}.dynamodb"
    ec2                  = "com.amazonaws.${data.aws_region.current.name}.ec2"
    ec2messages          = "com.amazonaws.${data.aws_region.current.name}.ec2messages"
    ssm                  = "com.amazonaws.${data.aws_region.current.name}.ssm"
    ssmmessages          = "com.amazonaws.${data.aws_region.current.name}.ssmmessages"
    ecr_api              = "com.amazonaws.${data.aws_region.current.name}.ecr.api"
    ecr_dkr              = "com.amazonaws.${data.aws_region.current.name}.ecr.dkr"
    logs                 = "com.amazonaws.${data.aws_region.current.name}.logs"
    kms                  = "com.amazonaws.${data.aws_region.current.name}.kms"
    secretsmanager       = "com.amazonaws.${data.aws_region.current.name}.secretsmanager"
    rds                  = "com.amazonaws.${data.aws_region.current.name}.rds"
    sns                  = "com.amazonaws.${data.aws_region.current.name}.sns"
    sqs                  = "com.amazonaws.${data.aws_region.current.name}.sqs"
    lambda               = "com.amazonaws.${data.aws_region.current.name}.lambda"
    ecs                  = "com.amazonaws.${data.aws_region.current.name}.ecs"
    ecs_agent            = "com.amazonaws.${data.aws_region.current.name}.ecs-agent"
    ecs_telemetry        = "com.amazonaws.${data.aws_region.current.name}.ecs-telemetry"
    elasticloadbalancing = "com.amazonaws.${data.aws_region.current.name}.elasticloadbalancing"
    autoscaling          = "com.amazonaws.${data.aws_region.current.name}.autoscaling"
    athena               = "com.amazonaws.${data.aws_region.current.name}.athena"
    cloudformation       = "com.amazonaws.${data.aws_region.current.name}.cloudformation"
    cloudtrail           = "com.amazonaws.${data.aws_region.current.name}.cloudtrail"
    cloudwatch           = "com.amazonaws.${data.aws_region.current.name}.monitoring"
    events               = "com.amazonaws.${data.aws_region.current.name}.events"
    execute_api          = "com.amazonaws.${data.aws_region.current.name}.execute-api"
    kinesis_streams      = "com.amazonaws.${data.aws_region.current.name}.kinesis-streams"
    kinesis_firehose     = "com.amazonaws.${data.aws_region.current.name}.kinesis-firehose"
    sagemaker_api        = "com.amazonaws.${data.aws_region.current.name}.sagemaker.api"
    sagemaker_runtime    = "com.amazonaws.${data.aws_region.current.name}.sagemaker.runtime"
    servicecatalog       = "com.amazonaws.${data.aws_region.current.name}.servicecatalog"
    sts                  = "com.amazonaws.${data.aws_region.current.name}.sts"
    transfer             = "com.amazonaws.${data.aws_region.current.name}.transfer"
    glue                 = "com.amazonaws.${data.aws_region.current.name}.glue"
    sagemaker_notebook   = "com.amazonaws.${data.aws_region.current.name}.notebook"
    elasticache          = "com.amazonaws.${data.aws_region.current.name}.elasticache"
  }

  # Gateway endpoints (S3 and DynamoDB)
  gateway_endpoints = {
    for k, v in var.endpoints : k => v
    if v.type == "Gateway"
  }

  # Interface endpoints
  interface_endpoints = {
    for k, v in var.endpoints : k => v
    if v.type == "Interface"
  }
}

data "aws_region" "current" {}

#------------------------------------------------------------------------------
# Security Group for Interface Endpoints
#------------------------------------------------------------------------------
resource "aws_security_group" "interface_endpoints" {
  count = length(local.interface_endpoints) > 0 ? 1 : 0

  name_prefix = "${local.name_prefix}-vpce-"
  description = "Security group for VPC Interface Endpoints"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-vpce-sg"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

#------------------------------------------------------------------------------
# Gateway Endpoints (S3, DynamoDB)
#------------------------------------------------------------------------------
resource "aws_vpc_endpoint" "gateway" {
  for_each = local.gateway_endpoints

  vpc_id            = var.vpc_id
  service_name      = local.service_names[each.key]
  vpc_endpoint_type = "Gateway"

  route_table_ids = each.value.route_table_ids

  policy = lookup(each.value, "policy", null)

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-vpce-${each.key}"
    },
    lookup(each.value, "tags", {})
  )
}

#------------------------------------------------------------------------------
# Interface Endpoints
#------------------------------------------------------------------------------
resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_endpoints

  vpc_id            = var.vpc_id
  service_name      = local.service_names[each.key]
  vpc_endpoint_type = "Interface"

  subnet_ids = each.value.subnet_ids

  security_group_ids = length(lookup(each.value, "security_group_ids", [])) > 0 ? each.value.security_group_ids : [aws_security_group.interface_endpoints[0].id]

  private_dns_enabled = lookup(each.value, "private_dns_enabled", true)
  policy              = lookup(each.value, "policy", null)

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-vpce-${each.key}"
    },
    lookup(each.value, "tags", {})
  )
}

#------------------------------------------------------------------------------
# Cost Estimation Output
#------------------------------------------------------------------------------
locals {
  # Interface endpoint costs: $0.01/hour per AZ + $0.01/GB data processed
  interface_endpoint_count = length(local.interface_endpoints)
  avg_azs_per_endpoint     = length(var.subnet_ids_for_estimation) > 0 ? length(var.subnet_ids_for_estimation) : 2

  # Monthly cost estimation
  interface_endpoint_hourly_cost = local.interface_endpoint_count * local.avg_azs_per_endpoint * 0.01
  interface_endpoint_monthly_cost = local.interface_endpoint_hourly_cost * 730

  # Gateway endpoints are free
  estimated_monthly_cost = local.interface_endpoint_monthly_cost
}
