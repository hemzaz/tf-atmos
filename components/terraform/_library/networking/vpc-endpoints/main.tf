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
    s3                   = "com.amazonaws.${data.aws_region.current.region}.s3"
    dynamodb             = "com.amazonaws.${data.aws_region.current.region}.dynamodb"
    ec2                  = "com.amazonaws.${data.aws_region.current.region}.ec2"
    ec2messages          = "com.amazonaws.${data.aws_region.current.region}.ec2messages"
    ssm                  = "com.amazonaws.${data.aws_region.current.region}.ssm"
    ssmmessages          = "com.amazonaws.${data.aws_region.current.region}.ssmmessages"
    ecr_api              = "com.amazonaws.${data.aws_region.current.region}.ecr.api"
    ecr_dkr              = "com.amazonaws.${data.aws_region.current.region}.ecr.dkr"
    logs                 = "com.amazonaws.${data.aws_region.current.region}.logs"
    kms                  = "com.amazonaws.${data.aws_region.current.region}.kms"
    secretsmanager       = "com.amazonaws.${data.aws_region.current.region}.secretsmanager"
    rds                  = "com.amazonaws.${data.aws_region.current.region}.rds"
    sns                  = "com.amazonaws.${data.aws_region.current.region}.sns"
    sqs                  = "com.amazonaws.${data.aws_region.current.region}.sqs"
    lambda               = "com.amazonaws.${data.aws_region.current.region}.lambda"
    ecs                  = "com.amazonaws.${data.aws_region.current.region}.ecs"
    ecs_agent            = "com.amazonaws.${data.aws_region.current.region}.ecs-agent"
    ecs_telemetry        = "com.amazonaws.${data.aws_region.current.region}.ecs-telemetry"
    elasticloadbalancing = "com.amazonaws.${data.aws_region.current.region}.elasticloadbalancing"
    autoscaling          = "com.amazonaws.${data.aws_region.current.region}.autoscaling"
    athena               = "com.amazonaws.${data.aws_region.current.region}.athena"
    cloudformation       = "com.amazonaws.${data.aws_region.current.region}.cloudformation"
    cloudtrail           = "com.amazonaws.${data.aws_region.current.region}.cloudtrail"
    cloudwatch           = "com.amazonaws.${data.aws_region.current.region}.monitoring"
    events               = "com.amazonaws.${data.aws_region.current.region}.events"
    execute_api          = "com.amazonaws.${data.aws_region.current.region}.execute-api"
    kinesis_streams      = "com.amazonaws.${data.aws_region.current.region}.kinesis-streams"
    kinesis_firehose     = "com.amazonaws.${data.aws_region.current.region}.kinesis-firehose"
    sagemaker_api        = "com.amazonaws.${data.aws_region.current.region}.sagemaker.api"
    sagemaker_runtime    = "com.amazonaws.${data.aws_region.current.region}.sagemaker.runtime"
    servicecatalog       = "com.amazonaws.${data.aws_region.current.region}.servicecatalog"
    sts                  = "com.amazonaws.${data.aws_region.current.region}.sts"
    transfer             = "com.amazonaws.${data.aws_region.current.region}.transfer"
    glue                 = "com.amazonaws.${data.aws_region.current.region}.glue"
    sagemaker_notebook   = "com.amazonaws.${data.aws_region.current.region}.notebook"
    elasticache          = "com.amazonaws.${data.aws_region.current.region}.elasticache"
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

  policy = each.value.policy

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-vpce-${each.key}"
    },
    each.value.tags
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

  security_group_ids = length(each.value.security_group_ids) > 0 ? each.value.security_group_ids : [aws_security_group.interface_endpoints[0].id]

  private_dns_enabled = each.value.private_dns_enabled
  policy              = each.value.policy

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-vpce-${each.key}"
    },
    each.value.tags
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
  interface_endpoint_hourly_cost  = local.interface_endpoint_count * local.avg_azs_per_endpoint * 0.01
  interface_endpoint_monthly_cost = local.interface_endpoint_hourly_cost * 730

  # Gateway endpoints are free
  estimated_monthly_cost = local.interface_endpoint_monthly_cost
}
