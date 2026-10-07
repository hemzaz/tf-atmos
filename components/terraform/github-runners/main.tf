# github-runners - self-hosted GitHub Actions runners in a VPC, so CI reaches
# private endpoints (the clusters' EKS API) that GitHub-hosted runners cannot.
#
# Cloud Posse aws-github-runners as plain resources: an Auto Scaling group of
# EC2 runners. Differences, each for a reason:
#   - Just-in-time runner configuration instead of a registration token. A
#     launch lifecycle hook holds each new instance while the jit function
#     (functions/jit) authenticates as a GitHub App and writes the instance's
#     single-use JIT configuration to SSM; the instance reads it, deletes it,
#     runs one job and leaves its group, lowering desired capacity. No
#     reusable registration credential exists on any host, and a copied
#     configuration is dead once its runner starts. Cloud Posse's component
#     reads a registration token (and its token-rotator component keeps one
#     in SSM); their philips-labs variant uses JIT the same way. CI raises
#     desired capacity by one (a +1 start policy, min_size 0) to start
#     runners, so there are no CPU
#     scaling policies, graceful scale-in hook or instance refresh.
#   - The App's private key is on this component's own KMS key, whose policy
#     lets only the jit function decrypt (no IAM delegation for Decrypt), so
#     no other role in the account can read it, whatever its IAM policy says.
#   - The instance role cannot read any SSM parameter but its own JIT one (an
#     explicit deny), and has a minimal Session Manager policy instead of
#     AmazonSSMManagedInstanceCore, which allows ssm:GetParameter* on *.
#   - A pinned, checksummed runner release; Amazon Linux 2023, IMDSv2 only, a
#     KMS-encrypted gp3 root volume, no public IP.
#
# Scanner suppressions are always inline and always carry an honest reason.

locals {
  enabled = var.enabled
  name    = "${var.tags["Environment"]}-${var.name}"

  partition  = one(data.aws_partition.current[*].partition)
  account_id = one(data.aws_caller_identity.current[*].account_id)

  app_key_parameter_name = coalesce(var.github_app_private_key_parameter_name, "/github/runners/${var.name}/app-private-key")
  app_key_parameter_arn  = local.enabled ? "arn:${local.partition}:ssm:${var.region}:${local.account_id}:parameter${local.app_key_parameter_name}" : null
  jit_parameter_prefix   = coalesce(var.jit_parameter_prefix, "/github/runners/${var.name}/jit")
  jit_parameter_arns     = local.enabled ? "arn:${local.partition}:ssm:${var.region}:${local.account_id}:parameter${local.jit_parameter_prefix}/*" : null
  # The group's ARN carries a generated id; this matches it by name.
  asg_arn_pattern = local.enabled ? "arn:${local.partition}:autoscaling:${var.region}:${local.account_id}:autoScalingGroup:*:autoScalingGroupName/${local.name}" : null

  user_data = templatefile("${path.module}/templates/user-data.sh", {
    pre_install          = var.userdata_pre_install
    post_install         = var.userdata_post_install
    runner_version       = var.runner_version
    runner_sha256        = var.runner_sha256
    jit_parameter_prefix = local.jit_parameter_prefix
    idle_timeout_seconds = var.idle_timeout_seconds
    allowed_refs         = var.allowed_refs
    github_scope         = var.github_scope
    job_started_hook     = trimspace(file("${path.module}/files/job-started.sh"))
  })
}

# The three policies as plain JSON, so the mock-provider tests can read them.
locals {
  ssm_via      = { "kms:ViaService" = "ssm.${var.region}.amazonaws.com" }
  account_root = local.enabled ? "arn:${local.partition}:iam::${local.account_id}:root" : null

  # The App key's own key. The account administers and encrypts with it (the
  # owner writes the key parameter) through IAM, but has no Decrypt: only the
  # jit function decrypts, for the App key parameter, through SSM.
  # PutKeyPolicy keeps the key recoverable.
  app_key_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountAdministersAndEncrypts"
        Effect    = "Allow"
        Principal = { AWS = local.account_root }
        Action = [
          "kms:CreateAlias", "kms:Describe*", "kms:Enable*", "kms:List*", "kms:Put*", "kms:Update*",
          "kms:Revoke*", "kms:Disable*", "kms:Get*", "kms:Delete*", "kms:TagResource", "kms:UntagResource",
          "kms:ScheduleKeyDeletion", "kms:CancelKeyDeletion", "kms:Encrypt", "kms:GenerateDataKey*", "kms:ReEncryptTo",
        ]
        Resource = "*"
      },
      {
        Sid       = "OnlyTheJitFunctionDecrypts"
        Effect    = "Allow"
        Principal = { AWS = one(aws_iam_role.jit[*].arn) }
        Action    = "kms:Decrypt"
        Resource  = "*"
        Condition = {
          StringEquals = merge(local.ssm_via, { "kms:EncryptionContext:PARAMETER_ARN" = local.app_key_parameter_arn })
        }
      },
    ]
  }

  jit_policy = {
    Version = "2012-10-17"
    Statement = [
      { Sid = "ReadAppKey", Effect = "Allow", Action = "ssm:GetParameter", Resource = local.app_key_parameter_arn },
      { Sid = "DecryptAppKey", Effect = "Allow", Action = "kms:Decrypt", Resource = one(aws_kms_key.app_key[*].arn) },
      {
        Sid      = "WriteJitConfigurations"
        Effect   = "Allow"
        Action   = ["ssm:PutParameter", "ssm:AddTagsToResource", "ssm:DeleteParameter"]
        Resource = local.jit_parameter_arns
      },
      {
        Sid       = "EncryptJitConfigurations"
        Effect    = "Allow"
        Action    = ["kms:Encrypt", "kms:GenerateDataKey"]
        Resource  = var.kms_key_arn
        Condition = { StringEquals = local.ssm_via }
      },
      # Release a launch, or end a failed one lowering desired capacity.
      {
        Sid      = "ReleaseOrEndLaunches"
        Effect   = "Allow"
        Action   = ["autoscaling:CompleteLifecycleAction", "autoscaling:TerminateInstanceInAutoScalingGroup"]
        Resource = local.asg_arn_pattern
      },
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = [for g in aws_cloudwatch_log_group.jit : "${g.arn}:*"]
      },
    ]
  }

  runner_policy = {
    Version = "2012-10-17"
    Statement = [
      # Its own JIT configuration only: the jit function tags each parameter
      # with the instance's ARN, which a role session on EC2 carries as
      # ec2:SourceInstanceARN.
      {
        Sid       = "OwnJitConfiguration"
        Effect    = "Allow"
        Action    = ["ssm:GetParameter", "ssm:DeleteParameter"]
        Resource  = local.jit_parameter_arns
        Condition = { StringEquals = { "aws:ResourceTag/RunnerInstanceArn" = "$${ec2:SourceInstanceARN}" } }
      },
      # A job runs on this host and can use these credentials: no parameter
      # but its own is ever readable, whatever else grants it.
      {
        Sid       = "NoOtherParameters"
        Effect    = "Deny"
        Action    = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath", "ssm:GetParameterHistory"]
        Resource  = "*"
        Condition = { StringNotEquals = { "aws:ResourceTag/RunnerInstanceArn" = "$${ec2:SourceInstanceARN}" } }
      },
      {
        Sid      = "DecryptOwnJitConfiguration"
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = var.kms_key_arn
        Condition = {
          StringEquals = local.ssm_via
          StringLike   = { "kms:EncryptionContext:PARAMETER_ARN" = local.jit_parameter_arns }
        }
      },
      # A runner removes itself from its own group after its job. IAM has no
      # key for the instance an Auto Scaling call targets, so this is scoped
      # to the group: a job could end a sibling runner in the same pool.
      # TODO(owner): accept or reject that in-pool denial of service (#303).
      { Sid = "LeaveOwnGroup", Effect = "Allow", Action = "autoscaling:TerminateInstanceInAutoScalingGroup", Resource = local.asg_arn_pattern },
      # Session Manager (debugging a runner without SSH) without
      # AmazonSSMManagedInstanceCore, which also grants ssm:GetParameter* on *.
      # The instance registers itself; the message channels take no
      # resource-level permissions.
      {
        Sid      = "SessionManagerRegistration"
        Effect   = "Allow"
        Action   = "ssm:UpdateInstanceInformation"
        Resource = local.enabled ? "arn:${local.partition}:ec2:${var.region}:${local.account_id}:instance/*" : null
      },
      {
        Sid    = "SessionManagerChannels"
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel", "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel",
          "ec2messages:AcknowledgeMessage", "ec2messages:DeleteMessage", "ec2messages:FailMessage",
          "ec2messages:GetEndpoint", "ec2messages:GetMessages", "ec2messages:SendReply",
        ]
        Resource = "*"
      },
    ]
  }
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

# =============================================================================
# The App key's own KMS key: only the jit function may decrypt with it.
# =============================================================================

resource "aws_kms_key" "app_key" {
  count = local.enabled ? 1 : 0

  description         = "${local.name}: the GitHub App private key (${local.app_key_parameter_name}); only the jit function decrypts"
  enable_key_rotation = true
  policy              = jsonencode(local.app_key_policy)
}

resource "aws_kms_alias" "app_key" {
  count = local.enabled ? 1 : 0

  name          = "alias/${local.name}-github-app"
  target_key_id = aws_kms_key.app_key[0].key_id
}

# =============================================================================
# The jit function
# =============================================================================

data "archive_file" "jit" {
  count = local.enabled ? 1 : 0

  type        = "zip"
  source_dir  = "${path.module}/functions/jit"
  excludes    = ["index.test.mjs"]
  output_path = "${path.module}/.archives/jit.zip"
  # Pinned so the hash depends only on file content (see the lambda component).
  output_file_mode = "0644"
}

data "aws_iam_policy_document" "lambda_assume" {
  count = local.enabled ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "jit" {
  count = local.enabled ? 1 : 0

  name               = "${local.name}-jit"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume[0].json
}

resource "aws_iam_role_policy" "jit" {
  count = local.enabled ? 1 : 0

  name   = "${local.name}-jit"
  role   = aws_iam_role.jit[0].id
  policy = jsonencode(local.jit_policy)
}

resource "aws_cloudwatch_log_group" "jit" {
  #checkov:skip=CKV_AWS_338:Retention is an input (log_retention_days) and a per-stack cost decision, as on the repo's other log groups
  count = local.enabled ? 1 : 0

  name              = "/aws/lambda/${local.name}-jit"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
}

resource "aws_lambda_function" "jit" {
  #checkov:skip=CKV_AWS_117:Calls the GitHub, SSM and Auto Scaling APIs only; outside a VPC it needs no NAT path or endpoints
  #checkov:skip=CKV_AWS_116:Invoked by EventBridge per lifecycle event; a failed launch is abandoned (the instance is replaced on the next scale-out), so a dead-letter queue would hold nothing to act on
  #checkov:skip=CKV_AWS_272:The package is built from this component's own source by archive_file; no signing profile
  #checkov:skip=CKV_AWS_50:One short call per launch; X-Ray would bill per trace for nothing to trace
  #checkov:skip=CKV_AWS_115:Concurrency follows launches, which max_size bounds; a reserved limit would only delay a scale-out
  count = local.enabled ? 1 : 0

  function_name    = "${local.name}-jit"
  description      = "Writes each ${local.name} instance's single-use GitHub Actions JIT runner configuration"
  role             = aws_iam_role.jit[0].arn
  runtime          = "nodejs22.x"
  handler          = "index.handler"
  filename         = data.archive_file.jit[0].output_path
  source_code_hash = data.archive_file.jit[0].output_base64sha256
  memory_size      = 128
  timeout          = 60
  kms_key_arn      = var.kms_key_arn

  # No secret here: the App key stays in SSM.
  environment {
    variables = {
      GITHUB_APP_ID          = var.github_app_id
      GITHUB_INSTALLATION_ID = var.github_app_installation_id
      GITHUB_SCOPE           = var.github_scope
      APP_KEY_PARAMETER      = local.app_key_parameter_name
      RUNNER_LABELS          = jsonencode(var.runner_labels)
      RUNNER_GROUP_ID        = tostring(var.runner_group_id)
      JIT_PARAMETER_PREFIX   = local.jit_parameter_prefix
      JIT_KMS_KEY_ID         = var.kms_key_arn
      PARTITION              = local.partition
      ACCOUNT_ID             = local.account_id
    }
  }

  depends_on = [aws_cloudwatch_log_group.jit, aws_iam_role_policy.jit]
}

# EventBridge invokes asynchronously; a retry would mint a second JIT
# configuration for an instance the first attempt already ended.
resource "aws_lambda_function_event_invoke_config" "jit" {
  count = local.enabled ? 1 : 0

  function_name          = aws_lambda_function.jit[0].function_name
  maximum_retry_attempts = 0
}

# A failed launch (the instance is ended, desired capacity lowered) or cleanup.
resource "aws_cloudwatch_metric_alarm" "jit_errors" {
  count = local.enabled ? 1 : 0

  alarm_name          = "${local.name}-jit-errors"
  alarm_description   = "The ${local.name} jit function failed: a runner launch was ended (see its log group)"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.jit[0].function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_sns_topic_arns
  ok_actions          = var.alarm_sns_topic_arns
}

resource "aws_cloudwatch_event_rule" "lifecycle" {
  count = local.enabled ? 1 : 0

  name        = "${local.name}-jit"
  description = "${local.name} launches (JIT configuration) and terminations (cleanup)"
  event_pattern = jsonencode({
    source      = ["aws.autoscaling"]
    detail-type = ["EC2 Instance-launch Lifecycle Action", "EC2 Instance Terminate Successful"]
    detail      = { AutoScalingGroupName = [local.name] }
  })
}

resource "aws_cloudwatch_event_target" "lifecycle" {
  count = local.enabled ? 1 : 0

  rule = aws_cloudwatch_event_rule.lifecycle[0].name
  arn  = aws_lambda_function.jit[0].arn
}

resource "aws_lambda_permission" "lifecycle" {
  count = local.enabled ? 1 : 0

  statement_id  = "AllowLifecycleEvents"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.jit[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.lifecycle[0].arn
}

# =============================================================================
# The runners
# =============================================================================

# Egress only: nothing connects to a runner. Whatever a job must reach (an EKS
# API) admits this group.
resource "aws_security_group" "runner" {
  #checkov:skip=CKV2_AWS_5:Attached to the runners through aws_launch_template.runner's network_interfaces; checkov's graph does not follow the count index in aws_security_group.runner[0].id
  count = local.enabled ? 1 : 0

  name_prefix = "${local.name}-"
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

data "aws_iam_policy_document" "instance_assume" {
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
  assume_role_policy = data.aws_iam_policy_document.instance_assume[0].json
}

resource "aws_iam_role_policy" "runner" {
  count = local.enabled ? 1 : 0

  name   = local.name
  role   = aws_iam_role.runner[0].id
  policy = jsonencode(local.runner_policy)
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

  # A runner leaves by terminating, never by stopping.
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

  # Scale-in never picks a runner (it may be mid-job): runners leave by
  # TerminateInstanceInAutoScalingGroup, which protection does not block.
  protect_from_scale_in = true

  # CI raises desired capacity (the start policy below); Terraform must not
  # reset it on every apply.
  # Capacity is never waited for: with min_size 0 there is nothing to wait for.
  wait_for_capacity_timeout = "0"

  launch_template {
    id      = aws_launch_template.runner[0].id
    version = aws_launch_template.runner[0].latest_version
  }

  # Every new instance waits here until the jit function has written its JIT
  # configuration (CONTINUE), or is terminated (ABANDON, also on timeout).
  initial_lifecycle_hook {
    name                 = "jit"
    lifecycle_transition = "autoscaling:EC2_INSTANCE_LAUNCHING"
    default_result       = "ABANDON"
    heartbeat_timeout    = var.lifecycle_heartbeat_timeout
  }

  # No instance_refresh: it would terminate runners in the middle of a job.
  # New instances start from the latest template version; runners leave
  # after one job, and max_instance_lifetime bounds the rest.

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

  # The jit function and its trigger exist before any instance launches.
  depends_on = [aws_cloudwatch_event_target.lifecycle, aws_lambda_permission.lifecycle]
}

# CI starts a runner by executing this policy (autoscaling:ExecutePolicy on
# this group only, iam/ci ci_runner_pool_names): an atomic +1, which Auto
# Scaling caps at max_size. CI cannot set any other capacity.
resource "aws_autoscaling_policy" "start" {
  count = local.enabled ? 1 : 0

  name                   = "${local.name}-start"
  autoscaling_group_name = aws_autoscaling_group.runner[0].name
  policy_type            = "SimpleScaling"
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 0
}
