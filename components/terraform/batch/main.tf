# AWS Batch: managed compute environments and the job queues that feed them,
# one map entry each (job definitions follow in a later change). Cloud Posse
# has no Batch component or module, so this follows the repo's own map-based
# components: <Environment>-<name>-<key> names, plain resources, validations in
# variables.tf.
#
# No service role is created: without service_role, Batch uses the
# AWSServiceRoleForBatch service-linked role (created on first use, which needs
# iam:CreateServiceLinkedRole on the deployer). EC2/SPOT environments get an
# instance profile with AmazonEC2ContainerServiceforEC2Role (unless they name
# their own) and a launch template that requires IMDSv2. The component creates
# no security groups; environments use the ones they are given.

locals {
  enabled = var.enabled
  prefix  = "${var.tags["Environment"]}-${var.name}"

  compute_environments = {
    for k, ce in var.compute_environments : k => merge(ce, {
      name    = "${local.prefix}-${k}"
      fargate = startswith(ce.type, "FARGATE")
    }) if local.enabled
  }

  ec2_compute_environments = { for k, ce in local.compute_environments : k => ce if !ce.fargate }

  instance_role_enabled = length([for ce in values(local.ec2_compute_environments) : ce if ce.instance_role == null]) > 0
  instance_role_name    = "${local.prefix}-instance"

  job_queues = { for k, q in var.job_queues : k => merge(q, { name = "${local.prefix}-${k}" }) if local.enabled }
}

data "aws_partition" "current" {}

# ECS container instance role (the AWS-documented ecsInstanceRole): the ECS
# agent on Batch's EC2 instances registers with the cluster, pulls images and
# writes logs with it. Jobs get their own credentials from their job role, not
# from this one (the launch template's hop limit 1 keeps them off IMDS).
resource "aws_iam_role" "instance" {
  count = local.instance_role_enabled ? 1 : 0

  name = local.instance_role_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = { Name = local.instance_role_name }

  lifecycle {
    precondition {
      condition     = length(local.instance_role_name) <= 64
      error_message = "The instance role name (<Environment>-<name>-instance, \"${local.instance_role_name}\") must be 64 characters or fewer."
    }
  }
}

resource "aws_iam_role_policy_attachment" "instance" {
  count = local.instance_role_enabled ? 1 : 0

  role       = aws_iam_role.instance[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "instance" {
  count = local.instance_role_enabled ? 1 : 0

  name = local.instance_role_name
  role = aws_iam_role.instance[0].name

  tags = { Name = local.instance_role_name }
}

# One launch template per EC2/SPOT environment, for the instance metadata
# options (the same IMDSv2-required, hop-limit-1 default as the eks and ec2
# components). Compute resource parameters set on the environment override the
# template, so only what the environment cannot set lives here.
resource "aws_launch_template" "this" {
  for_each = local.ec2_compute_environments

  name                   = each.value.name
  update_default_version = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = coalesce(each.value.metadata_http_put_response_hop_limit, 1)
  }

  tags = { Name = each.value.name }
}

resource "aws_batch_compute_environment" "this" {
  for_each = local.compute_environments

  name  = each.value.name
  type  = "MANAGED"
  state = each.value.state

  compute_resources {
    type               = each.value.type
    max_vcpus          = each.value.max_vcpus
    subnets            = each.value.subnet_ids
    security_group_ids = each.value.security_group_ids

    allocation_strategy = each.value.fargate ? null : coalesce(each.value.allocation_strategy, each.value.type == "SPOT" ? "SPOT_PRICE_CAPACITY_OPTIMIZED" : "BEST_FIT_PROGRESSIVE")
    min_vcpus           = each.value.fargate ? null : coalesce(each.value.min_vcpus, 0)
    desired_vcpus       = each.value.fargate ? null : each.value.desired_vcpus
    instance_type       = each.value.fargate ? null : coalesce(each.value.instance_types, ["default_x86_64"])
    instance_role       = each.value.fargate ? null : coalesce(each.value.instance_role, one(aws_iam_instance_profile.instance[*].arn))
    bid_percentage      = each.value.bid_percentage
    spot_iam_fleet_role = each.value.spot_iam_fleet_role

    # default_tags do not reach the instances Batch launches; these do.
    tags = each.value.fargate ? null : merge(var.tags, each.value.tags, { Name = each.value.name })

    dynamic "ec2_configuration" {
      for_each = each.value.fargate ? [] : [1]
      content {
        image_type        = coalesce(each.value.image_type, "ECS_AL2023")
        image_id_override = each.value.image_id_override
      }
    }

    dynamic "launch_template" {
      for_each = each.value.fargate ? [] : [aws_launch_template.this[each.key]]
      content {
        launch_template_id = launch_template.value.id
        version            = tostring(launch_template.value.latest_version)
      }
    }
  }

  dynamic "update_policy" {
    for_each = each.value.update_policy == null ? [] : [each.value.update_policy]
    content {
      job_execution_timeout_minutes = update_policy.value.job_execution_timeout_minutes
      terminate_jobs_on_update      = update_policy.value.terminate_jobs_on_update
    }
  }

  tags = merge(each.value.tags, { Name = each.value.name })

  depends_on = [aws_iam_role_policy_attachment.instance]

  lifecycle {
    precondition {
      condition     = length(each.value.name) <= 128
      error_message = "The compute environment name (<Environment>-<name>-<key>, \"${each.value.name}\") must be 128 characters or fewer."
    }
  }
}

resource "aws_batch_scheduling_policy" "this" {
  for_each = { for k, q in local.job_queues : k => q if q.fair_share_policy != null }

  name = each.value.name

  fair_share_policy {
    compute_reservation = each.value.fair_share_policy.compute_reservation
    share_decay_seconds = each.value.fair_share_policy.share_decay_seconds

    dynamic "share_distribution" {
      for_each = each.value.fair_share_policy.share_distribution
      content {
        share_identifier = share_distribution.value.share_identifier
        weight_factor    = share_distribution.value.weight_factor
      }
    }
  }

  tags = merge(each.value.tags, { Name = each.value.name })
}

resource "aws_batch_job_queue" "this" {
  for_each = local.job_queues

  name                  = each.value.name
  priority              = each.value.priority
  state                 = each.value.state
  scheduling_policy_arn = try(aws_batch_scheduling_policy.this[each.key].arn, null)

  dynamic "compute_environment_order" {
    for_each = each.value.compute_environment_order
    content {
      order = compute_environment_order.value.order
      compute_environment = (
        contains(keys(local.compute_environments), compute_environment_order.value.compute_environment)
        ? aws_batch_compute_environment.this[compute_environment_order.value.compute_environment].arn
        : compute_environment_order.value.compute_environment
      )
    }
  }

  tags = merge(each.value.tags, { Name = each.value.name })

  lifecycle {
    precondition {
      condition     = length(each.value.name) <= 128
      error_message = "The job queue name (<Environment>-<name>-<key>, \"${each.value.name}\") must be 128 characters or fewer."
    }
  }
}
