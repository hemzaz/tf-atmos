# Mock-provider tests: no AWS credentials, no network. Run from the component
# directory with `terraform init -backend=false && terraform test`.

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
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}

variables {
  region                            = "us-east-1"
  vpc_id                            = "vpc-0123456789abcdef0"
  subnet_ids                        = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
  kms_key_arn                       = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
  github_scope                      = "hemzaz/tf-atmos"
  runner_labels                     = ["fnx-testenv-01-dev"]
  runner_version                    = "2.329.0"
  runner_sha256                     = "0000000000000000000000000000000000000000000000000000000000000000"
  registration_token_parameter_name = "/github/runners/registration-token"
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
run "security_group_is_egress_only" {
  command = plan

  assert {
    condition     = aws_vpc_security_group_egress_rule.all[0].ip_protocol == "-1" && aws_vpc_security_group_egress_rule.all[0].cidr_ipv4 == "0.0.0.0/0"
    error_message = "Runners reach GitHub and the AWS APIs; nothing connects to them."
  }
}

run "user_data_registers_an_ephemeral_checksummed_runner" {
  command = plan

  assert {
    condition = alltrue([
      strcontains(local.user_data, "--ephemeral"),
      strcontains(local.user_data, "--disableupdate"),
      strcontains(local.user_data, "--url \"https://github.com/hemzaz/tf-atmos\""),
      strcontains(local.user_data, "--labels \"fnx-testenv-01-dev,$${INSTANCE_TYPE}\""),
      strcontains(local.user_data, "actions-runner-linux-x64-2.329.0.tar.gz"),
      strcontains(local.user_data, "sha256sum -c"),
      strcontains(local.user_data, "--name \"/github/runners/registration-token\""),
      strcontains(local.user_data, "--should-decrement-desired-capacity"),
    ])
    error_message = "The bootstrap verifies the pinned runner, registers it ephemeral with the labels, and leaves the group after its job."
  }
}

run "persistent_runner_installs_the_service" {
  command = plan

  variables {
    ephemeral = false
  }

  assert {
    condition     = !strcontains(local.user_data, "--ephemeral") && strcontains(local.user_data, "./svc.sh install runner")
    error_message = "ephemeral = false keeps Cloud Posse's long-lived runner service."
  }
}

run "runner_group_only_for_an_organization" {
  command = plan

  variables {
    github_scope = "my-org"
    runner_group = "terraform"
  }

  assert {
    condition     = strcontains(local.user_data, "--runnergroup \"terraform\"") && strcontains(local.user_data, "--url \"https://github.com/my-org\"")
    error_message = "An organization scope registers into its runner group."
  }
}

run "no_runner_group_for_a_repository" {
  command = plan

  assert {
    condition     = !strcontains(local.user_data, "--runnergroup")
    error_message = "A repository has no runner groups, so none is passed."
  }
}

run "disabled_creates_nothing" {
  command = plan

  variables {
    enabled = false
  }

  assert {
    condition     = length(aws_autoscaling_group.runner) == 0 && length(aws_security_group.runner) == 0
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
    runner_version = "v2.329.0"
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
