locals {
  # Default zone name pattern from root domain
  zone_name_pattern = trimsuffix(var.root_domain, ".")

  # Get the normalized record list
  normalized_records = {
    for id, record in var.records : id => {
      zone_id                          = try(aws_route53_zone.zones[record.zone_name].zone_id, try(data.aws_route53_zone.existing_zones[record.zone_name].zone_id))
      name                             = try(trimsuffix(record.name, "."), null)
      type                             = record.type
      ttl                              = try(record.ttl, var.zones[record.zone_name].default_ttl, 300)
      records                          = try(record.records, null)
      alias                            = try(record.alias, null)
      health_check_id                  = try(aws_route53_health_check.health_checks[record.health_check_id].id, record.health_check_id, null)
      set_identifier                   = try(record.set_identifier, null)
      weighted_routing_policy          = try(record.weighted_routing_policy, null)
      latency_routing_policy           = try(record.latency_routing_policy, null)
      geolocation_routing_policy       = try(record.geolocation_routing_policy, null)
      failover_routing_policy          = try(record.failover_routing_policy, null)
      multivalue_answer_routing_policy = try(record.multivalue_answer_routing_policy, null)
    }
  }
}

# Create reusable delegation sets if specified
resource "aws_route53_delegation_set" "delegation_sets" {
  for_each = var.delegation_sets

  reference_name = each.value.reference_name
}

# Root zone - conditionally create if requested
resource "aws_route53_zone" "root_zone" {
  count = var.create_root_zone ? 1 : 0

  name          = var.root_domain
  comment       = "Root domain zone for ${var.root_domain}"
  force_destroy = false

  tags = merge(
    var.tags,
    {
      Name = var.root_domain
      Type = "Root"
    }
  )
}

# Data source for existing zones (if not created)
data "aws_route53_zone" "existing_zones" {
  for_each = { for k, z in var.zones : k => z if !contains(keys(aws_route53_zone.zones), k) }

  name         = each.value.name
  private_zone = length(each.value.vpc_associations) > 0
  provider     = var.multi_account_dns_delegation ? aws.dns_account : aws
}

# Create all the requested zones
resource "aws_route53_zone" "zones" {
  for_each = var.zones

  name          = each.value.name
  comment       = each.value.comment
  force_destroy = each.value.force_destroy

  dynamic "vpc" {
    for_each = [for vpc_id in each.value.vpc_associations : vpc_id]
    content {
      vpc_id = vpc.value
    }
  }

  delegation_set_id = try(
    aws_route53_delegation_set.delegation_sets[each.value.delegation_set_id].id,
    each.value.delegation_set_id,
    null
  )

  tags = merge(
    var.tags,
    each.value.tags,
    {
      Name = each.value.name
    }
  )

  # Use DNS account if multi-account setup
  provider = var.multi_account_dns_delegation && !length(each.value.vpc_associations) > 0 ? aws.dns_account : aws
}

# Setup DNS query logging if enabled
resource "aws_route53_query_log" "query_logging" {
  for_each = {
    for k, zone in var.zones : k => zone
    if zone.enable_query_logging
  }

  depends_on = [aws_route53_zone.zones]

  cloudwatch_log_group_arn = lookup(
    each.value.query_logging_config,
    "cloudwatch_log_group_arn",
    aws_cloudwatch_log_group.dns_query_logs[each.key].arn
  )

  zone_id = aws_route53_zone.zones[each.key].zone_id
}

# Create log groups for DNS query logging if needed
resource "aws_cloudwatch_log_group" "dns_query_logs" {
  for_each = {
    for k, zone in var.zones : k => zone
    if zone.enable_query_logging &&
    !contains(keys(lookup(zone, "query_logging_config", {})), "cloudwatch_log_group_arn")
  }

  name              = "/aws/route53/${each.value.name}/queries"
  retention_in_days = lookup(each.value.query_logging_config, "retention_days", 30)
  kms_key_id        = lookup(each.value.query_logging_config, "kms_key_id", null)

  tags = merge(
    var.tags,
    each.value.tags,
    {
      Name = "/aws/route53/${each.value.name}/queries"
    }
  )
}

# Create DNS records
resource "aws_route53_record" "records" {
  for_each = local.normalized_records

  zone_id = each.value.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = each.value.alias != null ? null : each.value.ttl
  records = each.value.alias != null ? null : each.value.records

  dynamic "alias" {
    for_each = each.value.alias != null ? [each.value.alias] : []
    content {
      name                   = alias.value.name
      zone_id                = alias.value.zone_id
      evaluate_target_health = lookup(alias.value, "evaluate_target_health", true)
    }
  }

  health_check_id = each.value.health_check_id
  set_identifier  = each.value.set_identifier

  dynamic "weighted_routing_policy" {
    for_each = each.value.weighted_routing_policy != null ? [each.value.weighted_routing_policy] : []
    content {
      weight = weighted_routing_policy.value.weight
    }
  }

  dynamic "latency_routing_policy" {
    for_each = each.value.latency_routing_policy != null ? [each.value.latency_routing_policy] : []
    content {
      region = latency_routing_policy.value.region
    }
  }

  dynamic "geolocation_routing_policy" {
    for_each = each.value.geolocation_routing_policy != null ? [each.value.geolocation_routing_policy] : []
    content {
      continent   = lookup(geolocation_routing_policy.value, "continent", null)
      country     = lookup(geolocation_routing_policy.value, "country", null)
      subdivision = lookup(geolocation_routing_policy.value, "subdivision", null)
    }
  }

  dynamic "failover_routing_policy" {
    for_each = each.value.failover_routing_policy != null ? [each.value.failover_routing_policy] : []
    content {
      type = failover_routing_policy.value.type
    }
  }

  multivalue_answer_routing_policy = each.value.multivalue_answer_routing_policy
}

# Create health checks
resource "aws_route53_health_check" "health_checks" {
  for_each = var.health_checks

  fqdn              = each.value.fqdn
  ip_address        = each.value.ip_address
  port              = each.value.port
  type              = each.value.type
  resource_path     = each.value.resource_path
  failure_threshold = each.value.failure_threshold
  request_interval  = each.value.request_interval

  search_string = each.value.type == "HTTP_STR_MATCH" || each.value.type == "HTTPS_STR_MATCH" ? each.value.search_string : null

  measure_latency    = each.value.measure_latency
  invert_healthcheck = each.value.invert_healthcheck

  dynamic "regions" {
    for_each = each.value.regions
    content {
      name = regions.value
    }
  }

  tags = merge(
    var.tags,
    each.value.tags,
    {
      Name = each.value.name
    }
  )
}

# Route53 Traffic Policy - for complex routing scenarios
resource "aws_route53_traffic_policy" "traffic_policies" {
  for_each = var.traffic_policies

  name     = each.value.name
  comment  = each.value.comment
  document = each.value.document
}

resource "aws_route53_traffic_policy_version" "policy_versions" {
  for_each = var.traffic_policies

  traffic_policy_id = aws_route53_traffic_policy.traffic_policies[each.key].id
  document          = each.value.document
  comment           = each.value.version_comment
}

# VPC associations for private hosted zones
resource "aws_route53_zone_association" "vpc_associations" {
  for_each = var.vpc_dns_resolution

  vpc_id     = each.value.vpc_id
  vpc_region = each.value.vpc_region != null ? each.value.vpc_region : var.region
  zone_id = try(
    aws_route53_zone.zones[each.value.associated_zones[0]].id,
    data.aws_route53_zone.existing_zones[each.value.associated_zones[0]].id
  )

  depends_on = [
    aws_route53_zone.zones,
    data.aws_route53_zone.existing_zones
  ]
}