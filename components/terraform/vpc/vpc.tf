# availability_zone_ids resolve to this account's AZ names, as Cloud Posse
# aws-dynamic-subnets does with a zone-id filter.
data "aws_availability_zones" "by_id" {
  count = var.availability_zone_ids != null ? 1 : 0

  filter {
    name   = "zone-id"
    values = var.availability_zone_ids
  }
}

locals {
  az_name_by_id = var.availability_zone_ids == null ? {} : zipmap(
    data.aws_availability_zones.by_id[0].zone_ids,
    data.aws_availability_zones.by_id[0].names,
  )
  availability_zones = var.availability_zone_ids == null ? var.availability_zones : [
    for id in var.availability_zone_ids : lookup(local.az_name_by_id, id, null)
  ]

  # Subnets keyed by CIDR so adding or removing one does not renumber the others
  private_subnets  = { for i, cidr in var.private_subnets : cidr => { index = i, az = local.availability_zones[i] } }
  public_subnets   = { for i, cidr in var.public_subnets : cidr => { index = i, az = local.availability_zones[i] } }
  database_subnets = { for i, cidr in var.database_subnets : cidr => { index = i, az = local.availability_zones[i % length(local.availability_zones)] } }

  # The instance id: <Environment>-vpc-<name> (ue1-vpc-main), or
  # <Environment>-vpc for the default name. It names the VPC and starts the
  # account- and region-unique flow-logs names (flow-logs.tf); the subnet and
  # internet gateway Name tags start with it too, so vpc/main and vpc/services
  # differ in the console (the default name keeps <Environment>-<resource>).
  id         = var.name == "vpc" ? "${var.tags["Environment"]}-vpc" : "${var.tags["Environment"]}-vpc-${var.name}"
  tag_prefix = var.name == "vpc" ? var.tags["Environment"] : local.id
}

resource "aws_vpc" "main" {
  cidr_block           = var.ipv4_primary_cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = local.id }

  lifecycle {
    precondition {
      condition     = alltrue([for az in local.availability_zones : az != null])
      error_message = "Every availability_zone_ids entry must be an AZ ID of this account's region."
    }
  }
}

resource "aws_subnet" "private" {
  for_each          = local.private_subnets
  vpc_id            = aws_vpc.main.id
  cidr_block        = each.key
  availability_zone = each.value.az

  tags = merge(var.private_subnets_additional_tags, { Name = "${local.tag_prefix}-private-subnet-${each.value.index + 1}" })
}

resource "aws_subnet" "public" {
  for_each                = local.public_subnets
  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.key
  availability_zone       = each.value.az
  map_public_ip_on_launch = var.map_public_ip_on_launch

  tags = merge(var.public_subnets_additional_tags, { Name = "${local.tag_prefix}-public-subnet-${each.value.index + 1}" })
}

resource "aws_subnet" "database" {
  for_each          = local.database_subnets
  vpc_id            = aws_vpc.main.id
  cidr_block        = each.key
  availability_zone = each.value.az

  tags = merge(
    var.tags,
    {
      Name = "${local.tag_prefix}-database-subnet-${each.value.index + 1}"
      Type = "Database"
    }
  )
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${local.tag_prefix}-igw" }
}
