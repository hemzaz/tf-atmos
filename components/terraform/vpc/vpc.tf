locals {
  # Subnets keyed by CIDR so adding or removing one does not renumber the others
  private_subnets  = { for i, cidr in var.private_subnets : cidr => { index = i, az = var.azs[i] } }
  public_subnets   = { for i, cidr in var.public_subnets : cidr => { index = i, az = var.azs[i] } }
  database_subnets = { for i, cidr in var.database_subnets : cidr => { index = i, az = var.azs[i % length(var.azs)] } }
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "${var.tags["Environment"]}-vpc" }
}

resource "aws_subnet" "private" {
  for_each          = local.private_subnets
  vpc_id            = aws_vpc.main.id
  cidr_block        = each.key
  availability_zone = each.value.az

  tags = merge(var.private_subnets_additional_tags, { Name = "${var.tags["Environment"]}-private-subnet-${each.value.index + 1}" })
}

resource "aws_subnet" "public" {
  for_each          = local.public_subnets
  vpc_id            = aws_vpc.main.id
  cidr_block        = each.key
  availability_zone = each.value.az

  tags = merge(var.public_subnets_additional_tags, { Name = "${var.tags["Environment"]}-public-subnet-${each.value.index + 1}" })
}

resource "aws_subnet" "database" {
  for_each          = local.database_subnets
  vpc_id            = aws_vpc.main.id
  cidr_block        = each.key
  availability_zone = each.value.az

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-database-subnet-${each.value.index + 1}"
      Type = "Database"
    }
  )
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${var.tags["Environment"]}-igw" }
}