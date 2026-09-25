# One Step Functions state machine per instance, modelled on Cloud Posse's
# aws-step-functions component (https://github.com/cloudposse-terraform-components/aws-step-functions,
# which wraps cloudposse/terraform-aws-step-functions). Written as plain
# resources, like the other root components. Cloud Posse's own module also
# creates the execution role by default (its `existing_iam_role_arn` input is
# optional, for callers who already have one); this component always creates
# its own, scoped by trust-policy condition to this state machine's own ARN,
# with iam_policies adding whatever the definition's Tasks call directly.
# Logging always goes to a /aws/vendedlogs/states/<Environment>-<name> log
# group (the prefix AWS requires for Step Functions log delivery), encrypted
# with kms_key_arn.
# events_role_enabled additionally creates an EventBridge invoke role, for use
# as an eventbridge instance's target role_arn.
#
# Policies are built with jsonencode() (as in this repo's lambda component)
# rather than aws_iam_policy_document, so every one of them is a plain value
# computable at plan time from variables/locals/data sources alone.

locals {
  enabled = var.enabled
  name    = "${var.tags["Environment"]}-${var.name}"

  events_role_enabled = local.enabled && var.events_role_enabled
  logging_enabled     = local.enabled && var.logging_configuration.level != "OFF"
}

data "aws_caller_identity" "current" {}

# The state machine's ARN only depends on its name, which is known before it
# exists, so the execution role's trust policy can scope aws:SourceArn to it
# without a create-before-create dependency cycle.
locals {
  state_machine_arn = "arn:aws:states:${var.region}:${data.aws_caller_identity.current.account_id}:stateMachine:${local.name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "states.amazonaws.com" }
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          "aws:SourceArn"     = local.state_machine_arn
        }
      }
    }]
  })

  # The permissions AWS documents as required on a state machine's execution
  # role to deliver history events to CloudWatch Logs; the log delivery API
  # takes no resource-level permissions, so the logs:* statement is unscoped
  # (Resource "*"), as in AWS's own example policy for it. The second
  # statement is the execution role's own KMS grant for that delivery (step 3
  # of docs.aws.amazon.com/step-functions/latest/dg/encryption-at-rest.html):
  # the log-delivery data key is generated under encryption context
  # kms:EncryptionContext:SourceArn = the destination log group's ARN, a
  # different context than the state machine's own kms_policy statement
  # below, so it needs its own statement, scoped to this account's log groups
  # in this region.
  logging_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowStepFunctionsLogDelivery"
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups",
        ]
        Resource = "*"
      },
      {
        Sid      = "AllowLogDeliveryKMSUsage"
        Effect   = "Allow"
        Action   = ["kms:GenerateDataKey"]
        Resource = var.kms_key_arn
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:SourceArn" = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      },
    ]
  })

  # AWS requires kms:Decrypt/kms:GenerateDataKey on the CMK for the execution
  # role itself to run executions of this state machine (decrypt the
  # definition, encrypt/decrypt execution history) when it uses a customer
  # managed key (encryption_configuration below); kms/main's key policy only
  # delegates to the account root, which this role does not inherit
  # implicitly. (CreateStateMachine/UpdateStateMachine instead need
  # kms:DescribeKey/kms:GenerateDataKey on the *deployer's* caller role — the
  # one running `atmos terraform apply` — which the root-account delegation
  # already covers.) Scoped to this state machine's own ARN via the
  # encryption context Step Functions sets on every KMS call it makes for the
  # definition/execution history (step 2 of
  # docs.aws.amazon.com/step-functions/latest/dg/encryption-at-rest.html), so
  # this role can only use the key for this state machine, never another
  # resource sharing the same CMK.
  kms_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "AllowStateMachineKMSUsage"
      Effect   = "Allow"
      Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
      Resource = var.kms_key_arn
      Condition = {
        StringEquals = {
          "kms:EncryptionContext:aws:states:stateMachineArn" = local.state_machine_arn
        }
      }
    }]
  })

  # The permissions AWS documents as required to enable X-Ray tracing on a
  # state machine (the AWSXRayDaemonWriteAccess managed policy's actions).
  tracing_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowXRayTracing"
      Effect = "Allow"
      Action = [
        "xray:PutTraceSegments",
        "xray:PutTelemetryRecords",
        "xray:GetSamplingRules",
        "xray:GetSamplingTargets",
        "xray:GetSamplingStatisticSummaries",
      ]
      Resource = "*"
    }]
  })

  custom_policy = jsonencode({
    Version = "2012-10-17"
    # Condition is only rendered when a statement sets conditions: groups
    # each statement's conditions by test operator (StringEquals, ArnLike,
    # ...), and within a test operator, by condition key, so a statement can
    # carry conditions of different operators or keys at once.
    Statement = [for s in var.iam_policies : merge(
      {
        Sid      = s.sid
        Effect   = coalesce(s.effect, "Allow")
        Action   = s.actions
        Resource = s.resources
      },
      length(coalesce(s.conditions, [])) > 0 ? {
        Condition = {
          for test in distinct([for c in s.conditions : c.test]) :
          test => { for c in s.conditions : c.variable => c.values if c.test == test }
        }
      } : {}
    )]
  })

  events_assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "events.amazonaws.com" }
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })
}

resource "aws_cloudwatch_log_group" "this" {
  # checkov:skip=CKV_AWS_338:Retention mirrors the repo's other log groups (log_retention_days, default 90) and is a per-stack cost decision, not a module one.
  count = local.enabled ? 1 : 0

  name              = "/aws/vendedlogs/states/${local.name}"
  kms_key_id        = var.kms_key_arn
  retention_in_days = var.log_retention_days

  tags = { Name = "/aws/vendedlogs/states/${local.name}" }
}

resource "aws_iam_role" "this" {
  count = local.enabled ? 1 : 0

  name               = "${local.name}-role"
  assume_role_policy = local.assume_role_policy

  tags = { Name = "${local.name}-role" }
}

resource "aws_iam_role_policy" "kms" {
  # Always on (not conditioned on logging/tracing): encryption_configuration
  # below is unconditional, so the state machine's own KMS grant is too.
  count = local.enabled ? 1 : 0

  name   = "${local.name}-kms"
  role   = aws_iam_role.this[0].id
  policy = local.kms_policy
}

resource "aws_iam_role_policy" "logging" {
  count = local.logging_enabled ? 1 : 0

  name   = "${local.name}-logging"
  role   = aws_iam_role.this[0].id
  policy = local.logging_policy
}

resource "aws_iam_role_policy" "tracing" {
  count = local.enabled && var.tracing_enabled ? 1 : 0

  name   = "${local.name}-tracing"
  role   = aws_iam_role.this[0].id
  policy = local.tracing_policy
}

resource "aws_iam_role_policy" "custom" {
  count = local.enabled && length(var.iam_policies) > 0 ? 1 : 0

  name   = "${local.name}-custom"
  role   = aws_iam_role.this[0].id
  policy = local.custom_policy
}

resource "aws_sfn_state_machine" "this" {
  count = local.enabled ? 1 : 0

  name       = local.name
  role_arn   = aws_iam_role.this[0].arn
  type       = var.type
  definition = jsonencode(var.definition)

  logging_configuration {
    level                  = var.logging_configuration.level
    include_execution_data = var.logging_configuration.include_execution_data
    log_destination        = local.logging_enabled ? "${aws_cloudwatch_log_group.this[0].arn}:*" : null
  }

  tracing_configuration {
    enabled = var.tracing_enabled
  }

  # Not part of Cloud Posse's component, which predates this feature: encrypt
  # the definition and execution history with the same key as the log group.
  encryption_configuration {
    type                              = "CUSTOMER_MANAGED_KMS_KEY"
    kms_key_id                        = var.kms_key_arn
    kms_data_key_reuse_period_seconds = 60
  }

  tags = { Name = local.name }

  # AWS validates the role's KMS/log-delivery/tracing permissions when the
  # state machine is created or updated.
  depends_on = [aws_iam_role_policy.kms, aws_iam_role_policy.logging, aws_iam_role_policy.tracing, aws_iam_role_policy.custom]

  lifecycle {
    precondition {
      condition     = length(local.name) <= 80
      error_message = "The state machine name (<Environment>-<name>, currently \"${local.name}\") must be 80 characters or fewer."
    }
  }
}

# An EventBridge rule targeting this machine needs a role Step Functions
# accepts as an invoker (this repo's eventbridge component's targets.role_arn
# is required for a states target). Cloud Posse's component does not create
# one, since it is only needed by an eventbridge consumer, not by every state
# machine; created here, opt-in, because the consuming eventbridge instance
# has no way to create a role scoped to a machine it does not own.
resource "aws_iam_role" "events" {
  count = local.events_role_enabled ? 1 : 0

  name               = "${local.name}-events-role"
  assume_role_policy = local.events_assume_role_policy

  tags = { Name = "${local.name}-events-role" }
}

resource "aws_iam_role_policy" "events_invoke" {
  count = local.events_role_enabled ? 1 : 0

  name = "${local.name}-events-invoke"
  role = aws_iam_role.events[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "StartThisStateMachineOnly"
      Effect   = "Allow"
      Action   = "states:StartExecution"
      Resource = aws_sfn_state_machine.this[0].arn
    }]
  })
}
