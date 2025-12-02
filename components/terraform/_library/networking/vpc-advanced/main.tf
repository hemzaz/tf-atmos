locals {
  name_prefix = "${var.name_prefix}-${var.environment}"

  # Calculate number of NAT Gateways needed
  nat_gateway_count = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : length(var.availability_zones)) : 0

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
    s3             = "com.amazonaws.${data.aws_region.current.name}.s3"
    dynamodb       = "com.amazonaws.${data.aws_region.current.name}.dynamodb"
    ec2            = "com.amazonaws.${data.aws_region.current.name}.ec2"
    ec2messages    = "com.amazonaws.${data.aws_region.current.name}.ec2messages"
    ssm            = "com.amazonaws.${data.aws_region.current.name}.ssm"
    ssmmessages    = "com.amazonaws.${data.aws_region.current.name}.ssmmessages"
    ecr_api        = "com.amazonaws.${data.aws_region.current.name}.ecr.api"
    ecr_dkr        = "com.amazonaws.${data.aws_region.current.name}.ecr.dkr"
    logs           = "com.amazonaws.${data.aws_region.current.name}.logs"
    kms            = "com.amazonaws.${data.aws_region.current.name}.kms"
    secretsmanager = "com.amazonaws.${data.aws_region.current.name}.secretsmanager"
    rds            = "com.amazonaws.${data.aws_region.current.name}.rds"
    sns            = "com.amazonaws.${data.aws_region.current.name}.sns"
    sqs            = "com.amazonaws.${data.aws_region.current.name}.sqs"
    lambda         = "com.amazonaws.${data.aws_region.current.name}.lambda"
    ecs            = "com.amazonaws.${data.aws_region.current.name}.ecs"
    ecs_agent      = "com.amazonaws.${data.aws_region.current.name}.ecs-agent"
    ecs_telemetry  = "com.amazonaws.${data.aws_region.current.name}.ecs-telemetry"
    elasticloadbalancing = "com.amazonaws.${data.aws_region.current.name}.elasticloadbalancing"
    autoscaling    = "com.amazonaws.${data.aws_region.current.name}.autoscaling"
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
# IPv6 CIDR Block Association
#------------------------------------------------------------------------------
resource "aws_vpc_ipv6_cidr_block_association" "this" {
  count = var.enable_ipv6 ? 1 : 0

  vpc_id = aws_vpc.this.id
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
  count = length(var.public_subnets)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnets[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  ipv6_cidr_block                 = var.enable_ipv6 ? cidrsubnet(aws_vpc.this.ipv6_cidr_block, 8, count.index) : null
  assign_ipv6_address_on_creation = var.enable_ipv6

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-public-${var.availability_zones[count.index]}"
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
  count = length(var.public_subnets)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

#------------------------------------------------------------------------------
# NAT Gateways
#------------------------------------------------------------------------------
resource "aws_eip" "nat" {
  count = local.nat_gateway_count

  domain = "vpc"

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-nat-eip-${count.index + 1}"
    }
  )

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count = local.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-nat-${var.availability_zones[count.index]}"
    }
  )

  depends_on = [aws_internet_gateway.this]
}

#------------------------------------------------------------------------------
# Private Subnets
#------------------------------------------------------------------------------
resource "aws_subnet" "private" {
  count = length(var.private_subnets)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = var.availability_zones[count.index]

  ipv6_cidr_block                 = var.enable_ipv6 ? cidrsubnet(aws_vpc.this.ipv6_cidr_block, 8, count.index + length(var.public_subnets)) : null
  assign_ipv6_address_on_creation = var.enable_ipv6

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-private-${var.availability_zones[count.index]}"
      Tier = "private"
    }
  )
}

resource "aws_route_table" "private" {
  count = length(var.private_subnets)

  vpc_id = aws_vpc.this.id

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-private-rt-${var.availability_zones[count.index]}"
      Tier = "private"
    }
  )
}

resource "aws_route" "private_nat_gateway" {
  count = var.enable_nat_gateway ? length(var.private_subnets) : 0

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = var.single_nat_gateway ? aws_nat_gateway.this[0].id : aws_nat_gateway.this[count.index].id
}

resource "aws_route_table_association" "private" {
  count = length(var.private_subnets)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

#------------------------------------------------------------------------------
# Database Subnets
#------------------------------------------------------------------------------
resource "aws_subnet" "database" {
  count = length(var.database_subnets)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.database_subnets[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-database-${var.availability_zones[count.index]}"
      Tier = "database"
    }
  )
}

resource "aws_route_table" "database" {
  count = length(var.database_subnets)

  vpc_id = aws_vpc.this.id

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-database-rt-${var.availability_zones[count.index]}"
      Tier = "database"
    }
  )
}

resource "aws_route_table_association" "database" {
  count = length(var.database_subnets)

  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.database[count.index].id
}

resource "aws_db_subnet_group" "this" {
  count = length(var.database_subnets) > 0 ? 1 : 0

  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = aws_subnet.database[*].id

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
  subnet_ids         = aws_subnet.private[*].id

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

# Routes to Transit Gateway
resource "aws_route" "private_transit_gateway" {
  for_each = var.enable_transit_gateway ? var.transit_gateway_routes : {}

  route_table_id         = aws_route_table.private[0].id
  destination_cidr_block = each.key
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
    public   = aws_subnet.public[*].id
    private  = aws_subnet.private[*].id
    database = aws_subnet.database[*].id
  }

  route_table_tier_map = {
    public   = aws_route_table.public[*].id
    private  = aws_route_table.private[*].id
    database = aws_route_table.database[*].id
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

  security_group_ids  = lookup(each.value, "security_group_ids", null)
  private_dns_enabled = each.value.service_type == "Interface" ? lookup(each.value, "private_dns_enabled", true) : null
  policy              = lookup(each.value, "policy", null)

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-vpce-${each.key}"
    }
  )
}
