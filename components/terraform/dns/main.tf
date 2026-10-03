locals {
  # Public zones move to the DNS account when multi-account delegation is enabled;
  # private zones stay with their VPCs in this account
  dns_account_zone_keys = toset([
    for k, z in var.zones : k if var.multi_account_dns_delegation && length(z.vpc_associations) == 0
  ])

  # Delegation sets must live in the same account as the zones that use them
  local_zone_delegation_sets = toset(compact([
    for k, z in var.zones : z.delegation_set_id if !contains(local.dns_account_zone_keys, k)
  ]))
  dns_account_delegation_set_keys = toset([
    for k in local.dns_account_zone_keys : var.zones[k].delegation_set_id
    if var.zones[k].delegation_set_id != null && contains(keys(var.delegation_sets), coalesce(var.zones[k].delegation_set_id, "-"))
  ])

  # All managed zones, regardless of which account's provider created them
  managed_zones = merge(aws_route53_zone.zones, aws_route53_zone.dns_account_zones)

  # Default zone name pattern from root domain

  # Get the normalized record list: var.records plus one NS record per zone
  # with a parent_zone, delegating it from that parent (Cloud Posse
  # dns-delegated's pattern, for a subzone whose parent is in this instance).
  normalized_records = merge(local.explicit_records, local.delegation_records)

  # ttl: Cloud Posse dns-delegated hardcodes 30 on root_ns; here it is var.delegation_ttl (default 30).
  delegation_records = {
    for k, zone in var.zones : "delegation_${k}" => {
      zone_id                          = local.managed_zones[zone.parent_zone].zone_id
      name                             = trimsuffix(zone.name, ".")
      type                             = "NS"
      ttl                              = var.delegation_ttl
      records                          = local.managed_zones[k].name_servers
      alias                            = null
      health_check_id                  = null
      set_identifier                   = null
      weighted_routing_policy          = null
      latency_routing_policy           = null
      geolocation_routing_policy       = null
      failover_routing_policy          = null
      multivalue_answer_routing_policy = null
      # The NS record lives with the parent zone
      dns_account = contains(local.dns_account_zone_keys, zone.parent_zone)
    } if zone.parent_zone != null
  }

  explicit_records = {
    for id, record in var.records : id => {
      zone_id                          = try(local.managed_zones[record.zone_name].zone_id, try(data.aws_route53_zone.existing_zones[record.zone_name].zone_id))
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
      # Records follow their zone into the DNS account
      dns_account = contains(local.dns_account_zone_keys, record.zone_name)
    }
  }
}

# Create reusable delegation sets if specified
resource "aws_route53_delegation_set" "delegation_sets" {
  for_each = {
    for k, ds in var.delegation_sets : k => ds
    if !contains(local.dns_account_delegation_set_keys, k) || contains(local.local_zone_delegation_sets, k)
  }

  reference_name = each.value.reference_name
}

resource "aws_route53_delegation_set" "dns_account_delegation_sets" {
  provider = aws.dns_account
  for_each = { for k, ds in var.delegation_sets : k => ds if contains(local.dns_account_delegation_set_keys, k) }

  reference_name = each.value.reference_name
}

# Root zone - conditionally create if requested
resource "aws_route53_zone" "root_zone" {
  #checkov:skip=CKV2_AWS_38:TODO(owner): DNSSEC is not modelled for any zone (it needs an asymmetric KMS key in us-east-1 and a DS record at the registrar); no stack creates this zone (create_root_zone: false)
  #checkov:skip=CKV2_AWS_39:No stack creates this zone (create_root_zone: false); the zones a stack does create get query logging through zones.<key>.enable_query_logging
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
  for_each = { for k, z in var.zones : k => z if !contains(keys(local.managed_zones), k) }

  name         = each.value.name
  private_zone = length(each.value.vpc_associations) > 0
}

# Create all the requested zones (provider meta-arguments must be static, so zones
# hosted in the DNS account are split into dns_account_zones below)
resource "aws_route53_zone" "zones" {
  for_each = { for k, z in var.zones : k => z if !contains(local.dns_account_zone_keys, k) }

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
}

resource "aws_route53_zone" "dns_account_zones" {
  provider = aws.dns_account
  for_each = { for k, z in var.zones : k => z if contains(local.dns_account_zone_keys, k) }

  name          = each.value.name
  comment       = each.value.comment
  force_destroy = each.value.force_destroy

  delegation_set_id = try(
    aws_route53_delegation_set.dns_account_delegation_sets[each.value.delegation_set_id].id,
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
}

# Create DNS records
resource "aws_route53_record" "records" {
  for_each = { for id, record in local.normalized_records : id => record if !record.dns_account }

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
      evaluate_target_health = alias.value.evaluate_target_health
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

# Records in zones hosted in the DNS account (health checks referenced here must also
# exist in that account; health_checks created by this component live in the main account)
resource "aws_route53_record" "dns_account_records" {
  provider = aws.dns_account
  for_each = { for id, record in local.normalized_records : id => record if record.dns_account }

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
      evaluate_target_health = alias.value.evaluate_target_health
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

  regions = length(each.value.regions) > 0 ? each.value.regions : null

  tags = merge(
    var.tags,
    each.value.tags,
    {
      Name = each.value.name
    }
  )
}

# Route53 Traffic Policy - for complex routing scenarios. Updating the document creates
# a new policy version (aws_route53_traffic_policy_version does not exist in the provider).
resource "aws_route53_traffic_policy" "traffic_policies" {
  for_each = var.traffic_policies

  name     = each.value.name
  comment  = each.value.comment
  document = each.value.document
}

# VPC associations for private hosted zones
resource "aws_route53_zone_association" "vpc_associations" {
  for_each = var.vpc_dns_resolution

  vpc_id     = each.value.vpc_id
  vpc_region = each.value.vpc_region != null ? each.value.vpc_region : var.region
  zone_id = try(
    local.managed_zones[each.value.associated_zones[0]].id,
    data.aws_route53_zone.existing_zones[each.value.associated_zones[0]].id
  )

  depends_on = [
    aws_route53_zone.zones,
    aws_route53_zone.dns_account_zones,
    data.aws_route53_zone.existing_zones
  ]
}
