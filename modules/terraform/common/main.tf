# Common module - naming, tagging and environment defaults consumed by outputs.tf.
# (outputs.tf referenced these locals and data sources, but they were never defined.)

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name_prefix    = coalesce(var.custom_name_prefix, "${var.namespace}-${var.environment}-${var.stage}")
  component_name = "${local.name_prefix}-${var.component_name}"
  dns_name       = lower(replace(local.component_name, "_", "-"))

  common_tags = merge(
    {
      Namespace          = var.namespace
      Environment        = var.environment
      Stage              = var.stage
      Component          = var.component_name
      Project            = var.project_name
      Application        = var.application_name
      BusinessUnit       = var.business_unit
      CostCenter         = var.cost_center
      Owner              = var.owner
      DataClassification = var.data_classification
      BackupRequired     = tostring(var.backup_required)
      ManagedBy          = "Terraform"
    },
    length(var.compliance_frameworks) > 0 ? { Compliance = join(",", var.compliance_frameworks) } : {},
    var.additional_tags
  )

  env_config = {
    dev = {
      enable_monitoring   = var.enable_dev_monitoring
      storage_encrypted   = var.enable_encryption_at_rest
      enable_multi_az     = false
      enable_backups      = var.backup_required
      backup_window       = coalesce(var.backup_window, "03:00-04:00")
      maintenance_window  = coalesce(var.maintenance_window, "sun:04:00-sun:05:00")
      deletion_protection = coalesce(var.deletion_protection, false)
    }
    staging = {
      enable_monitoring   = var.enable_monitoring
      storage_encrypted   = var.enable_encryption_at_rest
      enable_multi_az     = var.enable_multi_az
      enable_backups      = var.backup_required
      backup_window       = coalesce(var.backup_window, "03:00-04:00")
      maintenance_window  = coalesce(var.maintenance_window, "sun:04:00-sun:05:00")
      deletion_protection = coalesce(var.deletion_protection, false)
    }
    prod = {
      enable_monitoring   = true
      storage_encrypted   = true
      enable_multi_az     = true
      enable_backups      = true
      backup_window       = coalesce(var.backup_window, "03:00-04:00")
      maintenance_window  = coalesce(var.maintenance_window, "sun:04:00-sun:05:00")
      deletion_protection = coalesce(var.deletion_protection, true)
    }
  }
  current_env_config = local.env_config[var.environment]

  standard_ports = {
    ssh        = 22
    http       = 80
    https      = 443
    mysql      = 3306
    postgresql = 5432
    redis      = 6379
  }

  common_sg_rules = {
    https_ingress = {
      description = "HTTPS from allowed CIDR blocks"
      from_port   = local.standard_ports.https
      to_port     = local.standard_ports.https
      protocol    = "tcp"
      cidr_blocks = var.allowed_cidr_blocks
    }
    https_egress = {
      description = "HTTPS to AWS services"
      from_port   = local.standard_ports.https
      to_port     = local.standard_ports.https
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  kms_key_policy_statements = {
    root_access = {
      Sid       = "EnableRootUserPermissions"
      Effect    = "Allow"
      Principal = { AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action    = "kms:*"
      Resource  = "*"
    }
  }
}
