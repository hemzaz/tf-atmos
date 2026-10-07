# Mock-provider tests: no AWS credentials, no network. Run from the component
# directory with `terraform init -backend=false && terraform test`. The jit
# function's flow is tested with `node --test functions/jit/`.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_ssm_parameter" {
    defaults = { insecure_value = "ami-0123456789abcdef0" }
  }
  mock_resource "aws_iam_role" {
    override_during = plan
    defaults        = { arn = "arn:aws:iam::123456789012:role/test-github-runners-jit" }
  }
  mock_resource "aws_kms_key" {
    override_during = plan
    defaults        = { arn = "arn:aws:kms:us-east-1:123456789012:key/app-key" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    override_during = plan
    defaults        = { arn = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/lambda/test-github-runners-jit" }
  }
  # Only the assume-role documents are data sources; the other policies are
  # locals (local.app_key_policy, local.jit_policy, local.runner_policy).
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}

variables {
  region                     = "us-east-1"
  vpc_id                     = "vpc-0123456789abcdef0"
  subnet_ids                 = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
  kms_key_arn                = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
  github_scope               = "hemzaz/tf-atmos"
  runner_labels              = ["fnx-ue1-dev"]
  runner_version             = "2.337.0"
  runner_sha256              = "0000000000000000000000000000000000000000000000000000000000000000"
  github_app_id              = "123456"
  github_app_installation_id = "7654321"
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
}

run "defaults_scale_from_zero_on_t3_medium" {
  command = plan

  assert {
    condition = (
      aws_autoscaling_group.runner[0].min_size == 0
      && aws_autoscaling_group.runner[0].name == "test-github-runners"
      && aws_launch_template.runner[0].instance_type == "t3.medium"
    )
    error_message = "Defaults: min 0, t3.medium, named <Environment>-github-runners."
  }
}

run "every_launch_waits_for_its_jit_configuration" {
  command = plan

  assert {
    condition = anytrue([
      for h in aws_autoscaling_group.runner[0].initial_lifecycle_hook :
      h.lifecycle_transition == "autoscaling:EC2_INSTANCE_LAUNCHING" && h.default_result == "ABANDON" && h.heartbeat_timeout == 300
    ])
    error_message = "A launch hook holds each instance, abandoning it if the jit function does not answer."
  }

  assert {
    condition = (
      jsondecode(aws_cloudwatch_event_rule.lifecycle[0].event_pattern).detail.AutoScalingGroupName == ["test-github-runners"]
      && contains(jsondecode(aws_cloudwatch_event_rule.lifecycle[0].event_pattern)["detail-type"], "EC2 Instance-launch Lifecycle Action")
      && contains(jsondecode(aws_cloudwatch_event_rule.lifecycle[0].event_pattern)["detail-type"], "EC2 Instance Terminate Successful")
    )
    error_message = "The jit function hears this group's launches and terminations only."
  }
}

run "jit_function_carries_no_secret" {
  command = plan

  assert {
    condition = (
      aws_lambda_function.jit[0].runtime == "nodejs22.x"
      && aws_lambda_function.jit[0].environment[0].variables["APP_KEY_PARAMETER"] == "/github/runners/github-runners/app-private-key"
      && aws_lambda_function.jit[0].environment[0].variables["GITHUB_SCOPE"] == "hemzaz/tf-atmos"
      && aws_lambda_function.jit[0].environment[0].variables["RUNNER_LABELS"] == "[\"fnx-ue1-dev\"]"
    )
    error_message = "The function gets the key's parameter name, the scope and the labels, never the key."
  }
}

run "jit_failures_alarm_and_are_not_retried" {
  command = plan

  variables {
    alarm_sns_topic_arns = ["arn:aws:sns:us-east-1:123456789012:alerts"]
  }

  assert {
    condition     = aws_lambda_function_event_invoke_config.jit[0].maximum_retry_attempts == 0
    error_message = "A retry would mint a second JIT configuration."
  }

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.jit_errors[0].metric_name == "Errors"
      && aws_cloudwatch_metric_alarm.jit_errors[0].threshold == 0
      && toset(aws_cloudwatch_metric_alarm.jit_errors[0].alarm_actions) == toset(["arn:aws:sns:us-east-1:123456789012:alerts"])
    )
    error_message = "Any jit error alarms to alarm_sns_topic_arns."
  }

  assert {
    condition = anytrue([
      for s in local.jit_policy.Statement :
      contains(flatten([s.Action]), "autoscaling:TerminateInstanceInAutoScalingGroup") && s.Resource == "arn:aws:autoscaling:us-east-1:123456789012:autoScalingGroup:*:autoScalingGroupName/test-github-runners"
    ])
    error_message = "The jit function may end a failed launch in its own group only."
  }
}

run "app_key_is_decrypted_by_the_jit_function_only" {
  command = plan

  assert {
    condition = alltrue([
      for s in local.app_key_policy.Statement :
      !contains(flatten([s.Action]), "kms:Decrypt") || s.Principal.AWS == "arn:aws:iam::123456789012:role/test-github-runners-jit"
    ])
    error_message = "Only the jit function's role may kms:Decrypt with the App key's key; the account root may administer and encrypt."
  }

  assert {
    condition = !anytrue([
      for s in local.app_key_policy.Statement : anytrue([for a in flatten([s.Action]) : contains(["kms:Create*", "kms:CreateGrant", "kms:*"], a)])
    ])
    error_message = "The key policy grants no kms:CreateGrant (no kms:Create* or kms:* either)."
  }

  assert {
    condition     = aws_kms_alias.app_key[0].name == "alias/test-github-runners-github-app" && aws_kms_key.app_key[0].enable_key_rotation
    error_message = "The App key's key is alias/<Environment>-<name>-github-app, rotated."
  }
}

run "instance_reads_only_its_own_parameter" {
  command = plan

  assert {
    condition = anytrue([
      for s in local.runner_policy.Statement :
      s.Effect == "Deny" && contains(flatten([s.Action]), "ssm:GetParameter") && s.Resource == "*"
      && s.Condition.StringNotEquals["aws:ResourceTag/RunnerInstanceArn"] == "$${ec2:SourceInstanceARN}"
    ])
    error_message = "An explicit deny keeps every parameter but the instance's own JIT one unreadable."
  }

  assert {
    condition = !anytrue([
      for s in local.runner_policy.Statement :
      s.Effect == "Allow" && contains(flatten([s.Action]), "ssm:GetParameters")
    ])
    error_message = "No allow of ssm:GetParameters (AmazonSSMManagedInstanceCore's is gone)."
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.additional) == 0
    error_message = "No managed policy is attached by default."
  }

  assert {
    condition = !anytrue([
      for s in local.runner_policy.Statement :
      anytrue([for a in flatten([s.Action]) : startswith(a, "autoscaling:")])
    ])
    error_message = "The runner role has no Auto Scaling action (it could end a sibling runner): runners leave through their lease."
  }
}

run "a_deleted_lease_ends_its_runner" {
  command = plan

  assert {
    condition = (
      jsondecode(aws_cloudwatch_event_rule.lease[0].event_pattern) == {
        source        = ["aws.ssm"]
        "detail-type" = ["Parameter Store Change"]
        detail = {
          operation = ["Delete"]
          name      = [{ prefix = "/github/runners/github-runners/jit/lease/" }]
        }
      }
      && aws_cloudwatch_event_target.lease[0].rule == "test-github-runners-lease"
      && aws_lambda_permission.lease[0].principal == "events.amazonaws.com"
      && aws_lambda_permission.lease[0].statement_id == "AllowLeaseEvents"
      && aws_lambda_function.jit[0].environment[0].variables["AUTOSCALING_GROUP_NAME"] == "test-github-runners"
    )
    error_message = "Deleting <prefix>/lease/<instance id> invokes the jit function, which ends that runner of this group."
  }

  assert {
    condition = anytrue([
      for s in local.jit_policy.Statement :
      contains(flatten([s.Action]), "autoscaling:DescribeAutoScalingInstances")
    ])
    error_message = "The jit function checks that a lease's instance is an InService runner of this group."
  }
}

run "a_refused_job_leaves_without_lowering_capacity" {
  command = plan

  assert {
    condition = alltrue([
      strcontains(local.user_data, "install -d -m 0700 -o runner -g runner /var/lib/runner-state"),
      strcontains(local.user_data, "REFUSED_MARKER='/var/lib/runner-state/refused'"),
      strcontains(local.user_data, "if [ -e \"$${REFUSED_MARKER}\" ]; then"),
    ])
    error_message = "A runner whose job the fork guard refused powers off with its lease kept, so the group replaces it."
  }
}

run "instances_are_hardened" {
  command = plan

  assert {
    condition = (
      aws_launch_template.runner[0].metadata_options[0].http_tokens == "required"
      && aws_launch_template.runner[0].metadata_options[0].http_put_response_hop_limit == 1
      && aws_launch_template.runner[0].network_interfaces[0].associate_public_ip_address == "false"
      && aws_launch_template.runner[0].block_device_mappings[0].ebs[0].encrypted == "true"
      && aws_launch_template.runner[0].block_device_mappings[0].ebs[0].kms_key_id == var.kms_key_arn
      && aws_launch_template.runner[0].instance_initiated_shutdown_behavior == "terminate"
    )
    error_message = "IMDSv2 with hop limit 1, no public IP, a KMS-encrypted root volume, terminate on shutdown."
  }
}

# The component declares no ingress rule resource at all; its one rule is egress.
run "security_group_is_egress_only_and_prefixed" {
  command = plan

  assert {
    condition = (
      aws_vpc_security_group_egress_rule.all[0].ip_protocol == "-1"
      && aws_security_group.runner[0].name_prefix == "test-github-runners-"
    )
    error_message = "Runners reach GitHub and the AWS APIs; nothing connects to them; the group name is a prefix (create_before_destroy)."
  }
}

run "user_data_runs_one_checksummed_jit_runner_and_always_leaves" {
  command = plan

  assert {
    condition = alltrue([
      strcontains(local.user_data, "trap terminate EXIT"),
      strcontains(local.user_data, "trap 'shutdown -h now' EXIT"),
      strcontains(local.user_data, "actions-runner-linux-x64-2.337.0.tar.gz"),
      strcontains(local.user_data, "sha256sum -c"),
      strcontains(local.user_data, "JIT_PARAMETER=\"/github/runners/github-runners/jit/$${INSTANCE_ID}\""),
      strcontains(local.user_data, "aws ssm delete-parameter"),
      strcontains(local.user_data, "./run.sh --jitconfig"),
      strcontains(local.user_data, "aws ssm delete-parameter --region \"$${REGION}\" --name \"/github/runners/github-runners/jit/lease/$${INSTANCE_ID}\""),
      strcontains(local.user_data, "sleep 600"),
      !strcontains(local.user_data, "terminate-instance-in-auto-scaling-group"),
      !strcontains(local.user_data, "config.sh"),
    ])
    error_message = "The bootstrap verifies the pinned runner, reads and deletes its JIT configuration, runs once, and leaves on any exit."
  }
}

run "disabled_creates_nothing" {
  command = plan

  variables {
    enabled = false
  }

  assert {
    condition     = length(aws_autoscaling_group.runner) == 0 && length(aws_lambda_function.jit) == 0 && length(aws_kms_key.app_key) == 0
    error_message = "enabled = false creates nothing."
  }
}

run "rejects_a_label_with_a_comma" {
  command = plan

  variables {
    runner_labels = ["a,b"]
  }

  expect_failures = [var.runner_labels]
}

run "rejects_a_v_prefixed_version" {
  command = plan

  variables {
    runner_version = "v2.337.0"
  }

  expect_failures = [var.runner_version]
}

run "rejects_a_short_checksum" {
  command = plan

  variables {
    runner_sha256 = "abc123"
  }

  expect_failures = [var.runner_sha256]
}

run "rejects_max_below_min" {
  command = plan

  variables {
    min_size = 3
    max_size = 2
  }

  expect_failures = [var.max_size]
}

run "rejects_a_non_numeric_app_id" {
  command = plan

  variables {
    github_app_id = "my-app"
  }

  expect_failures = [var.github_app_id]
}

run "every_pool_installs_the_fork_guard_hook" {
  command = plan

  assert {
    condition = alltrue([
      strcontains(local.user_data, "ACTIONS_RUNNER_HOOK_JOB_STARTED=/opt/runner-hooks/job-started.sh"),
      strcontains(local.user_data, "ALLOWED_SCOPE='hemzaz/tf-atmos'"),
      strcontains(local.user_data, "ALLOWED_REFS=''"),
      # The hook's rules (files/job-started.sh), rendered verbatim.
      strcontains(local.user_data, "push | workflow_dispatch | schedule | merge_group) ;;"),
      strcontains(local.user_data, ".pull_request.head.repo.full_name // empty"),
      strcontains(local.user_data, "*) refuse \"event '$event'\" ;;"),
    ])
    error_message = "Every pool's runners refuse fork pull requests and unlisted events in their job-started hook, whatever allowed_refs says."
  }
}

run "allowed_refs_fail_other_jobs_before_their_first_step" {
  command = plan

  variables {
    name         = "prod-runners"
    allowed_refs = ["refs/heads/master"]
  }

  assert {
    condition = alltrue([
      strcontains(local.user_data, "ALLOWED_REFS='refs/heads/master'"),
      strcontains(local.user_data, "JIT_PARAMETER=\"/github/runners/prod-runners/jit/$${INSTANCE_ID}\""),
    ])
    error_message = "A pool with allowed_refs hands them to its hook; its JIT path is per pool."
  }
}

run "ci_starts_runners_with_a_plus_one_policy_and_scale_in_spares_them" {
  command = plan

  assert {
    condition = (
      aws_autoscaling_group.runner[0].protect_from_scale_in
      && aws_autoscaling_policy.start[0].name == "test-github-runners-start"
      && aws_autoscaling_policy.start[0].adjustment_type == "ChangeInCapacity"
      && aws_autoscaling_policy.start[0].scaling_adjustment == 1
    )
    error_message = "CI's only lever is a +1 SimpleScaling policy (capped at max_size); scale-in never ends a runner mid-job."
  }
}

run "allowed_refs_rejects_a_pattern" {
  command = plan

  variables {
    allowed_refs = ["refs/heads/*"]
  }

  expect_failures = [var.allowed_refs]
}
