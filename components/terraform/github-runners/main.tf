# github-runners - self-hosted GitHub Actions runners in a VPC, so CI reaches
# private endpoints (the clusters' EKS API) that GitHub-hosted runners cannot.
#
# Cloud Posse aws-github-runners as plain resources: an Auto Scaling group of
# EC2 runners that register with a token read from SSM (kept fresh by the
# github-action-token-rotator component). Differences, each for a reason:
#   - ephemeral by default: one job per instance, which then leaves the group
#     and lowers desired capacity; CI raises desired capacity to start runners
#     (min_size 0), instead of CPU scaling policies on long-lived runners. So
#     no graceful scale-in hook either: an ephemeral runner deregisters itself.
#   - a pinned, checksummed runner release instead of "latest";
#   - Amazon Linux 2023 from its public SSM parameter, IMDSv2 only, a KMS
#     encrypted gp3 root volume, no public IP;
#   - the instance role has no ECR or cross-account grants: Terraform jobs get
#     AWS access from GitHub OIDC (the stack's iam/ci roles), not the instance.
#
# Scanner suppressions are always inline and always carry an honest reason.

locals {
  enabled = var.enabled
  name    = "${var.tags["Environment"]}-${var.name}"

  partition  = one(data.aws_partition.current[*].partition)
  account_id = one(data.aws_caller_identity.current[*].account_id)

  token_parameter_arn = local.enabled ? "arn:${local.partition}:ssm:${var.region}:${local.account_id}:parameter${var.registration_token_parameter_name}" : null
  # The group's ARN carries a generated id; this matches it by name.
  asg_arn_pattern = local.enabled ? "arn:${local.partition}:autoscaling:${var.region}:${local.account_id}:autoScalingGroup:*:autoScalingGroupName/${local.name}" : null

  user_data = templatefile("${path.module}/templates/user-data.sh", {
    pre_install          = var.userdata_pre_install
    post_install         = var.userdata_post_install
    runner_version       = var.runner_version
    runner_sha256        = var.runner_sha256
    token_parameter_name = var.registration_token_parameter_name
    github_scope         = var.github_scope
    labels               = join(",", var.runner_labels)
    # Only an organization has runner groups; a repository runner refuses one.
    runner_group         = strcontains(var.github_scope, "/") ? "" : var.runner_group
    ephemeral            = var.ephemeral
    idle_timeout_seconds = var.idle_timeout_seconds
  })
}

data "aws_partition" "current" {
  count = local.enabled ? 1 : 0
}

data "aws_caller_identity" "current" {
  count = local.enabled ? 1 : 0
}

data "aws_ssm_parameter" "ami" {
  count = local.enabled ? 1 : 0

  name = var.ami_ssm_parameter_name
}

# Egress only: nothing connects to a runner. Whatever a job must reach (an EKS
# API) admits this group.
resource "aws_security_group" "runner" {
  #checkov:skip=CKV2_AWS_5:Attached to the runners through aws_launch_template.runner's network_interfaces; checkov's graph does not follow the count index in aws_security_group.runner[0].id
  count = local.enabled ? 1 : 0

  name        = local.name
  description = "GitHub Actions runners (egress only)"
  vpc_id      = var.vpc_id

  tags = { Name = local.name }

  lifecycle {
    create_before_destroy = true
  }
}

#trivy:ignore:AVD-AWS-0104 Egress is unrestricted by policy (owner decision): a runner reaches GitHub and the AWS APIs, and the group has no ingress rule at all.
resource "aws_vpc_security_group_egress_rule" "all" {
  count = local.enabled ? 1 : 0

  security_group_id = aws_security_group.runner[0].id
  description       = "GitHub, the AWS APIs and in-VPC endpoints"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

data "aws_iam_policy_document" "assume" {
  count = local.enabled ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "runner" {
  count = local.enabled ? 1 : 0

  name               = local.name
  assume_role_policy = data.aws_iam_policy_document.assume[0].json
}

data "aws_iam_policy_document" "runner" {
  count = local.enabled ? 1 : 0

  statement {
    sid       = "ReadRegistrationToken"
    actions   = ["ssm:GetParameter"]
    resources = [local.token_parameter_arn]
  }

  statement {
    sid       = "DecryptRegistrationToken"
    actions   = ["kms:Decrypt"]
    resources = [var.kms_key_arn]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${var.region}.amazonaws.com"]
    }
  }

  # An ephemeral runner removes itself from its own group after its job.
  statement {
    sid       = "LeaveOwnGroup"
    actions   = ["autoscaling:TerminateInstanceInAutoScalingGroup"]
    resources = [local.asg_arn_pattern]
  }
}

resource "aws_iam_role_policy" "runner" {
  count = local.enabled ? 1 : 0

  name   = local.name
  role   = aws_iam_role.runner[0].id
  policy = data.aws_iam_policy_document.runner[0].json
}

# Session Manager for debugging a runner; no SSH key, no inbound port.
resource "aws_iam_role_policy_attachment" "ssm" {
  count = local.enabled ? 1 : 0

  role       = aws_iam_role.runner[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "additional" {
  for_each = local.enabled ? toset(var.runner_role_additional_policy_arns) : toset([])

  role       = aws_iam_role.runner[0].name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "runner" {
  count = local.enabled ? 1 : 0

  name = local.name
  role = aws_iam_role.runner[0].name
}

resource "aws_launch_template" "runner" {
  count = local.enabled ? 1 : 0

  name                   = local.name
  image_id               = data.aws_ssm_parameter.ami[0].insecure_value
  instance_type          = var.instance_type
  update_default_version = true
  user_data              = base64encode(local.user_data)

  # An ephemeral runner leaves by terminating, never by stopping.
  instance_initiated_shutdown_behavior = "terminate"

  iam_instance_profile {
    arn = aws_iam_instance_profile.runner[0].arn
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.runner[0].id]
    delete_on_termination       = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.root_volume_size
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = var.kms_key_arn
      delete_on_termination = true
    }
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = local.name })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(var.tags, { Name = local.name })
  }
}

resource "aws_autoscaling_group" "runner" {
  count = local.enabled ? 1 : 0

  name                  = local.name
  min_size              = var.min_size
  max_size              = var.max_size
  vpc_zone_identifier   = var.subnet_ids
  health_check_type     = "EC2"
  max_instance_lifetime = var.max_instance_lifetime

  # CI sets desired capacity; Terraform must not reset it on every apply.
  # Capacity is never waited for: with min_size 0 there is nothing to wait for.
  wait_for_capacity_timeout = "0"

  launch_template {
    id      = aws_launch_template.runner[0].id
    version = aws_launch_template.runner[0].latest_version
  }

  # No instance_refresh: it would terminate runners in the middle of a job.
  # New instances start from the latest template version; ephemeral ones
  # leave after one job, and max_instance_lifetime bounds the rest.

  dynamic "tag" {
    for_each = merge(var.tags, { Name = local.name })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = false
    }
  }

  lifecycle {
    ignore_changes = [desired_capacity]
  }
}
