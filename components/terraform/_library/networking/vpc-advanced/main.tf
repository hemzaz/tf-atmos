locals {
  name_prefix = "${var.name_prefix}-${var.environment}"

  # Subnets are positionally aligned with availability_zones and keyed by AZ
  public_azs   = slice(var.availability_zones, 0, length(var.public_subnets))
  private_azs  = slice(var.availability_zones, 0, length(var.private_subnets))
  database_azs = slice(var.availability_zones, 0, length(var.database_subnets))

  public_subnets   = { for i, cidr in var.public_subnets : var.availability_zones[i] => { cidr = cidr, ipv6_netnum = i } }
  private_subnets  = { for i, cidr in var.private_subnets : var.availability_zones[i] => { cidr = cidr, ipv6_netnum = i + length(var.public_subnets) } }
  database_subnets = { for i, cidr in var.database_subnets : var.availability_zones[i] => cidr }

  # NAT Gateways live in public subnets: one per public AZ, or a single one
  nat_gateway_azs   = var.enable_nat_gateway ? slice(local.public_azs, 0, var.single_nat_gateway ? min(1, length(local.public_azs)) : length(local.public_azs)) : []
  nat_gateway_count = length(local.nat_gateway_azs)

  # Common tags
  common_tags = merge(
    {
      Name        = local.name_prefix
      Environment = var.environment
      ManagedBy   = "Terraform"
      Module      = "vpc-advanced"
    },
    var.tags
  )

  # VPC Endpoint service names
  vpc_endpoint_services = {
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
  }
}

data "aws_region" "current" {}

#------------------------------------------------------------------------------
# VPC
#------------------------------------------------------------------------------
resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr

  enable_dns_hostnames             = var.enable_dns_hostnames
  enable_dns_support               = var.enable_dns_support
  assign_generated_ipv6_cidr_block = var.enable_ipv6

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-vpc"
    }
  )
}

#------------------------------------------------------------------------------
# DHCP Options
#------------------------------------------------------------------------------
resource "aws_vpc_dhcp_options" "this" {
  count = var.enable_dhcp_options ? 1 : 0

  domain_name         = var.dhcp_options_domain_name
  domain_name_servers = var.dhcp_options_domain_name_servers

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-dhcp-options"
    }
  )
}

resource "aws_vpc_dhcp_options_association" "this" {
  count = var.enable_dhcp_options ? 1 : 0

  vpc_id          = aws_vpc.this.id
  dhcp_options_id = aws_vpc_dhcp_options.this[0].id
}

#------------------------------------------------------------------------------
# Internet Gateway
#------------------------------------------------------------------------------
resource "aws_internet_gateway" "this" {
  count = length(var.public_subnets) > 0 ? 1 : 0

  vpc_id = aws_vpc.this.id

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-igw"
    }
  )
}

#------------------------------------------------------------------------------
# Public Subnets
#------------------------------------------------------------------------------
resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.key
  map_public_ip_on_launch = true

  ipv6_cidr_block                 = var.enable_ipv6 ? cidrsubnet(aws_vpc.this.ipv6_cidr_block, 8, each.value.ipv6_netnum) : null
  assign_ipv6_address_on_creation = var.enable_ipv6

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-public-${each.key}"
      Tier = "public"
    }
  )
}

resource "aws_route_table" "public" {
  count = length(var.public_subnets) > 0 ? 1 : 0

  vpc_id = aws_vpc.this.id

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-public-rt"
      Tier = "public"
    }
  )
}

resource "aws_route" "public_internet_gateway" {
  count = length(var.public_subnets) > 0 ? 1 : 0

  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id
}

resource "aws_route" "public_internet_gateway_ipv6" {
  count = var.enable_ipv6 && length(var.public_subnets) > 0 ? 1 : 0

  route_table_id              = aws_route_table.public[0].id
  destination_ipv6_cidr_block = "::/0"
  gateway_id                  = aws_internet_gateway.this[0].id
}

resource "aws_route_table_association" "public" {
  for_each = local.public_subnets

  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public[0].id
}

#------------------------------------------------------------------------------
# NAT Gateways
#------------------------------------------------------------------------------
resource "aws_eip" "nat" {
  for_each = toset(local.nat_gateway_azs)

  domain = "vpc"

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-nat-eip-${each.key}"
    }
  )

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  for_each = toset(local.nat_gateway_azs)

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-nat-${each.key}"
    }
  )

  depends_on = [aws_internet_gateway.this]
}

#------------------------------------------------------------------------------
# Private Subnets
#------------------------------------------------------------------------------
resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.cidr
  availability_zone = each.key

  ipv6_cidr_block                 = var.enable_ipv6 ? cidrsubnet(aws_vpc.this.ipv6_cidr_block, 8, each.value.ipv6_netnum) : null
  assign_ipv6_address_on_creation = var.enable_ipv6

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-private-${each.key}"
      Tier = "private"
    }
  )
}

resource "aws_route_table" "private" {
  for_each = local.private_subnets

  vpc_id = aws_vpc.this.id

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-private-rt-${each.key}"
      Tier = "private"
    }
  )
}

resource "aws_route" "private_nat_gateway" {
  for_each = {
    for az, subnet in local.private_subnets : az => subnet
    if local.nat_gateway_count > 0 && (var.single_nat_gateway || contains(local.nat_gateway_azs, az))
  }

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[var.single_nat_gateway ? local.nat_gateway_azs[0] : each.key].id
}

resource "aws_route_table_association" "private" {
  for_each = local.private_subnets

  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.private[each.key].id
}

#------------------------------------------------------------------------------
# Database Subnets
#------------------------------------------------------------------------------
resource "aws_subnet" "database" {
  for_each = local.database_subnets

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = each.key

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-database-${each.key}"
      Tier = "database"
    }
  )
}

resource "aws_route_table" "database" {
  for_each = local.database_subnets

  vpc_id = aws_vpc.this.id

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-database-rt-${each.key}"
      Tier = "database"
    }
  )
}

resource "aws_route_table_association" "database" {
  for_each = local.database_subnets

  subnet_id      = aws_subnet.database[each.key].id
  route_table_id = aws_route_table.database[each.key].id
}

resource "aws_db_subnet_group" "this" {
  count = length(var.database_subnets) > 0 ? 1 : 0

  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = [for az in local.database_azs : aws_subnet.database[az].id]

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-db-subnet-group"
    }
  )
}

#------------------------------------------------------------------------------
# VPN Gateway
#------------------------------------------------------------------------------
resource "aws_vpn_gateway" "this" {
  count = var.enable_vpn_gateway ? 1 : 0

  vpc_id          = aws_vpc.this.id
  amazon_side_asn = var.vpn_gateway_amazon_side_asn

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-vpn-gateway"
    }
  )
}

#------------------------------------------------------------------------------
# Transit Gateway Attachment
#------------------------------------------------------------------------------
resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  count = var.enable_transit_gateway ? 1 : 0

  transit_gateway_id = var.transit_gateway_id
  vpc_id             = aws_vpc.this.id
  subnet_ids         = [for az in local.private_azs : aws_subnet.private[az].id]

  dns_support                                     = "enable"
  ipv6_support                                    = var.enable_ipv6 ? "enable" : "disable"
  transit_gateway_default_route_table_association = true
  transit_gateway_default_route_table_propagation = true

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-tgw-attachment"
    }
  )
}

# Routes to Transit Gateway (added to every private route table)
resource "aws_route" "private_transit_gateway" {
  for_each = var.enable_transit_gateway ? {
    for pair in setproduct(local.private_azs, keys(var.transit_gateway_routes)) :
    "${pair[0]}-${pair[1]}" => { az = pair[0], cidr = pair[1] }
  } : {}

  route_table_id         = aws_route_table.private[each.value.az].id
  destination_cidr_block = each.value.cidr
  transit_gateway_id     = var.transit_gateway_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]
}

#------------------------------------------------------------------------------
# Default Security Group (Restricted)
#------------------------------------------------------------------------------
resource "aws_default_security_group" "this" {
  count = var.manage_default_security_group ? 1 : 0

  vpc_id = aws_vpc.this.id

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-default-sg-restricted"
    }
  )
}

#------------------------------------------------------------------------------
# VPC Flow Logs
#------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "flow_logs" {
  count = var.enable_flow_logs && var.flow_logs_destination_type == "cloud-watch-logs" ? 1 : 0

  name              = "/aws/vpc/${local.name_prefix}"
  retention_in_days = var.flow_logs_retention_days

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-flow-logs"
    }
  )
}

resource "aws_iam_role" "flow_logs" {
  count = var.enable_flow_logs && var.flow_logs_destination_type == "cloud-watch-logs" ? 1 : 0

  name = "${local.name_prefix}-vpc-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.enable_flow_logs && var.flow_logs_destination_type == "cloud-watch-logs" ? 1 : 0

  name = "${local.name_prefix}-vpc-flow-logs-policy"
  role = aws_iam_role.flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_flow_log" "this" {
  count = var.enable_flow_logs ? 1 : 0

  vpc_id          = aws_vpc.this.id
  traffic_type    = "ALL"
  iam_role_arn    = var.flow_logs_destination_type == "cloud-watch-logs" ? aws_iam_role.flow_logs[0].arn : null
  log_destination = var.flow_logs_destination_type == "cloud-watch-logs" ? aws_cloudwatch_log_group.flow_logs[0].arn : var.flow_logs_s3_bucket_arn

  log_destination_type = var.flow_logs_destination_type

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-flow-logs"
    }
  )
}

#------------------------------------------------------------------------------
# VPC Endpoints
#------------------------------------------------------------------------------
locals {
  # Map subnet tier names to actual subnet IDs
  subnet_tier_map = {
    public   = [for az in local.public_azs : aws_subnet.public[az].id]
    private  = [for az in local.private_azs : aws_subnet.private[az].id]
    database = [for az in local.database_azs : aws_subnet.database[az].id]
  }

  route_table_tier_map = {
    public   = aws_route_table.public[*].id
    private  = [for az in local.private_azs : aws_route_table.private[az].id]
    database = [for az in local.database_azs : aws_route_table.database[az].id]
  }
}

resource "aws_vpc_endpoint" "this" {
  for_each = var.enable_vpc_endpoints ? var.vpc_endpoints : {}

  vpc_id            = aws_vpc.this.id
  service_name      = local.vpc_endpoint_services[each.key]
  vpc_endpoint_type = each.value.service_type

  # For Gateway endpoints
  route_table_ids = each.value.service_type == "Gateway" ? flatten([
    for rt in each.value.route_table_ids :
    contains(["public", "private", "database"], rt) ? local.route_table_tier_map[rt] : [rt]
  ]) : null

  # For Interface endpoints
  subnet_ids = each.value.service_type == "Interface" ? flatten([
    for subnet in each.value.subnet_ids :
    contains(["public", "private", "database"], subnet) ? local.subnet_tier_map[subnet] : [subnet]
  ]) : null

  security_group_ids  = each.value.service_type == "Interface" ? each.value.security_group_ids : null
  private_dns_enabled = each.value.service_type == "Interface" ? each.value.private_dns_enabled : null
  policy              = each.value.policy

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-vpce-${each.key}"
    }
  )
}
