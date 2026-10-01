# Route53 public DNS query logging (zones.<key>.enable_query_logging).
#
# Route53 only publishes query logs to a CloudWatch Logs log group in
# us-east-1, in the account that owns the hosted zone, and only once a
# CloudWatch Logs resource policy in us-east-1 lets route53.amazonaws.com write
# to it (Route53 API reference, CreateQueryLoggingConfig). So the log groups,
# the resource policy and the KMS key encrypting the groups are all created in
# us-east-1, whatever var.region is, through the resource-level `region`
# argument (AWS provider v6 enhanced region support, the pattern
# _library/security/kms-multi-region uses for its replicas) instead of extra
# per-region provider aliases: the DNS-account zones keep using aws.dns_account
# and only override the region.
#
# Cloud Posse's dns-primary/dns-delegated components have no query logging, so
# the shape follows the AWS docs; the key mirrors vpc/flow-logs.tf's own
# flow-log key (account root plus the regional CloudWatch Logs principal,
# scoped by kms:EncryptionContext:aws:logs:arn).

locals {
  query_log_region = "us-east-1"

  query_logged_zones = { for k, zone in var.zones : k => zone if zone.enable_query_logging }

  # Zones whose log group this component creates (no caller-supplied group)
  query_log_groups = {
    for k, zone in local.query_logged_zones : k => zone
    if !contains(keys(zone.query_logging_config), "cloudwatch_log_group_arn")
  }

  query_logged_local_keys       = [for k in keys(local.query_logged_zones) : k if !contains(local.dns_account_zone_keys, k)]
  query_logged_dns_account_keys = [for k in keys(local.query_logged_zones) : k if contains(local.dns_account_zone_keys, k)]

  # This component's own key encrypts every log group it creates without a
  # caller-supplied query_logging_config.kms_key_id, one key per account
  create_query_log_key = length([
    for k, zone in local.query_log_groups : k
    if !contains(local.dns_account_zone_keys, k) && !contains(keys(zone.query_logging_config), "kms_key_id")
  ]) > 0
  create_dns_account_query_log_key = length([
    for k, zone in local.query_log_groups : k
    if contains(local.dns_account_zone_keys, k) && !contains(keys(zone.query_logging_config), "kms_key_id")
  ]) > 0

  # Resource policies and key aliases are account-wide names, and network/main
  # and network/services share an account: name them after this instance's
  # first query-logged zone (zone names are unique per instance).
  query_log_name_suffix = try(
    replace(trimsuffix(sort([for z in values(local.query_logged_zones) : lower(z.name)])[0], "."), ".", "-"),
    ""
  )

  query_log_group_arns = {
    for k, zone in local.query_logged_zones : k => lookup(
      zone.query_logging_config,
      "cloudwatch_log_group_arn",
      try(aws_cloudwatch_log_group.dns_query_logs[k].arn, aws_cloudwatch_log_group.dns_account_query_logs[k].arn, null)
    )
  }
}

data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

data "aws_caller_identity" "dns_account" {
  provider = aws.dns_account
  count    = length(local.query_logged_dns_account_keys) > 0 ? 1 : 0
}

# --- KMS keys (us-east-1) ----------------------------------------------------

resource "aws_kms_key" "query_logs" {
  count  = local.create_query_log_key ? 1 : 0
  region = local.query_log_region

  description             = "Route53 query log encryption (${local.query_log_name_suffix})"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  # A key policy cannot reference its own ARN; "*" means "this key".
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableAccountAdministration"
        Effect    = "Allow"
        Principal = { AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowCloudWatchLogsRoute53QueryLogGroups"
        Effect    = "Allow"
        Principal = { Service = "logs.${local.query_log_region}.amazonaws.com" }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*",
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:${data.aws_partition.current.partition}:logs:${local.query_log_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/route53/*"
          }
        }
      },
    ]
  })

  tags = merge(var.tags, { Name = "route53-query-logs-${local.query_log_name_suffix}" })
}

resource "aws_kms_alias" "query_logs" {
  count  = local.create_query_log_key ? 1 : 0
  region = local.query_log_region

  name          = "alias/route53-query-logs-${local.query_log_name_suffix}"
  target_key_id = aws_kms_key.query_logs[0].key_id
}

resource "aws_kms_key" "dns_account_query_logs" {
  provider = aws.dns_account
  count    = local.create_dns_account_query_log_key ? 1 : 0
  region   = local.query_log_region

  description             = "Route53 query log encryption (${local.query_log_name_suffix})"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableAccountAdministration"
        Effect    = "Allow"
        Principal = { AWS = "arn:${data.aws_partition.current.partition}:iam::${one(data.aws_caller_identity.dns_account[*].account_id)}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowCloudWatchLogsRoute53QueryLogGroups"
        Effect    = "Allow"
        Principal = { Service = "logs.${local.query_log_region}.amazonaws.com" }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*",
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:${data.aws_partition.current.partition}:logs:${local.query_log_region}:${one(data.aws_caller_identity.dns_account[*].account_id)}:log-group:/aws/route53/*"
          }
        }
      },
    ]
  })

  tags = merge(var.tags, { Name = "route53-query-logs-${local.query_log_name_suffix}" })
}

resource "aws_kms_alias" "dns_account_query_logs" {
  provider = aws.dns_account
  count    = local.create_dns_account_query_log_key ? 1 : 0
  region   = local.query_log_region

  name          = "alias/route53-query-logs-${local.query_log_name_suffix}"
  target_key_id = aws_kms_key.dns_account_query_logs[0].key_id
}

# --- Log groups (us-east-1) --------------------------------------------------

resource "aws_cloudwatch_log_group" "dns_query_logs" {
  for_each = { for k, zone in local.query_log_groups : k => zone if !contains(local.dns_account_zone_keys, k) }
  region   = local.query_log_region

  name              = "/aws/route53/${trimsuffix(each.value.name, ".")}/queries"
  retention_in_days = tonumber(lookup(each.value.query_logging_config, "retention_days", var.query_log_retention_in_days))
  kms_key_id        = lookup(each.value.query_logging_config, "kms_key_id", one(aws_kms_key.query_logs[*].arn))

  tags = merge(
    var.tags,
    each.value.tags,
    {
      Name = "/aws/route53/${trimsuffix(each.value.name, ".")}/queries"
    }
  )
}

resource "aws_cloudwatch_log_group" "dns_account_query_logs" {
  provider = aws.dns_account
  for_each = { for k, zone in local.query_log_groups : k => zone if contains(local.dns_account_zone_keys, k) }
  region   = local.query_log_region

  name              = "/aws/route53/${trimsuffix(each.value.name, ".")}/queries"
  retention_in_days = tonumber(lookup(each.value.query_logging_config, "retention_days", var.query_log_retention_in_days))
  kms_key_id        = lookup(each.value.query_logging_config, "kms_key_id", one(aws_kms_key.dns_account_query_logs[*].arn))

  tags = merge(
    var.tags,
    each.value.tags,
    {
      Name = "/aws/route53/${trimsuffix(each.value.name, ".")}/queries"
    }
  )
}

# --- Resource policies (us-east-1) -------------------------------------------
# One account-level policy per instance and account (CloudWatch Logs allows 10
# per region), limited to this instance's log groups and, against the confused
# deputy problem, to this account's query-logged hosted zones.

resource "aws_cloudwatch_log_resource_policy" "route53_query_logging" {
  count  = length(local.query_logged_local_keys) > 0 ? 1 : 0
  region = local.query_log_region

  policy_name = "route53-query-logging-${local.query_log_name_suffix}"
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "Route53QueryLogging"
        Effect    = "Allow"
        Principal = { Service = "route53.amazonaws.com" }
        Action    = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource  = [for k in local.query_logged_local_keys : "${local.query_log_group_arns[k]}:*"]
        Condition = {
          StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
          ArnLike      = { "aws:SourceArn" = [for k in local.query_logged_local_keys : aws_route53_zone.zones[k].arn] }
        }
      },
    ]
  })
}

resource "aws_cloudwatch_log_resource_policy" "dns_account_route53_query_logging" {
  provider = aws.dns_account
  count    = length(local.query_logged_dns_account_keys) > 0 ? 1 : 0
  region   = local.query_log_region

  policy_name = "route53-query-logging-${local.query_log_name_suffix}"
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "Route53QueryLogging"
        Effect    = "Allow"
        Principal = { Service = "route53.amazonaws.com" }
        Action    = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource  = [for k in local.query_logged_dns_account_keys : "${local.query_log_group_arns[k]}:*"]
        Condition = {
          StringEquals = { "aws:SourceAccount" = one(data.aws_caller_identity.dns_account[*].account_id) }
          ArnLike      = { "aws:SourceArn" = [for k in local.query_logged_dns_account_keys : aws_route53_zone.dns_account_zones[k].arn] }
        }
      },
    ]
  })
}

# --- Query logging configs ---------------------------------------------------
# Route53 checks the resource policy when the config is created, so it must
# exist first (InsufficientCloudWatchLogsResourcePolicy otherwise).

resource "aws_route53_query_log" "query_logging" {
  for_each = toset(local.query_logged_local_keys)

  cloudwatch_log_group_arn = local.query_log_group_arns[each.key]
  zone_id                  = aws_route53_zone.zones[each.key].zone_id

  depends_on = [aws_cloudwatch_log_resource_policy.route53_query_logging]
}

resource "aws_route53_query_log" "dns_account_query_logging" {
  provider = aws.dns_account
  for_each = toset(local.query_logged_dns_account_keys)

  cloudwatch_log_group_arn = local.query_log_group_arns[each.key]
  zone_id                  = aws_route53_zone.dns_account_zones[each.key].zone_id

  depends_on = [aws_cloudwatch_log_resource_policy.dns_account_route53_query_logging]
}
