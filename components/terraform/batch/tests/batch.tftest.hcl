# Mock-provider tests: no AWS credentials, no network. Run from the component
# directory with `terraform init -backend=false && terraform test`.

# override_during = plan: mocked computed values (ARNs, launch template
# version) are known at plan, so plan-only runs can assert on them.
mock_provider "aws" {
  override_during = plan

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_resource "aws_iam_instance_profile" {
    defaults = {
      arn = "arn:aws:iam::123456789012:instance-profile/test-batch-instance"
    }
  }

  mock_resource "aws_launch_template" {
    defaults = {
      id             = "lt-0123456789abcdef0"
      latest_version = 3
    }
  }
}

# Distinct ARNs per compute environment, so the queue tests can tell which one
# each compute_environment_order entry resolved to.
override_resource {
  override_during = plan
  target          = aws_batch_compute_environment.this["fargate"]
  values          = { arn = "arn:aws:batch:us-east-1:123456789012:compute-environment/test-batch-fargate" }
}

override_resource {
  override_during = plan
  target          = aws_batch_compute_environment.this["fargate-spot"]
  values          = { arn = "arn:aws:batch:us-east-1:123456789012:compute-environment/test-batch-fargate-spot" }
}

override_resource {
  override_during = plan
  target          = aws_batch_compute_environment.this["ec2"]
  values          = { arn = "arn:aws:batch:us-east-1:123456789012:compute-environment/test-batch-ec2" }
}

override_resource {
  override_during = plan
  target          = aws_batch_compute_environment.this["spot"]
  values          = { arn = "arn:aws:batch:us-east-1:123456789012:compute-environment/test-batch-spot" }
}

variables {
  region = "us-east-1"
  name   = "batch"
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
  compute_environments = {
    fargate = {
      type               = "FARGATE"
      max_vcpus          = 256
      subnet_ids         = ["subnet-aaa", "subnet-bbb"]
      security_group_ids = ["sg-batch"]
    }
    fargate-spot = {
      type               = "FARGATE_SPOT"
      max_vcpus          = 512
      subnet_ids         = ["subnet-aaa", "subnet-bbb"]
      security_group_ids = ["sg-batch"]
    }
    ec2 = {
      type               = "EC2"
      max_vcpus          = 128
      subnet_ids         = ["subnet-aaa"]
      security_group_ids = ["sg-batch"]
      update_policy      = {}
    }
    spot = {
      type               = "SPOT"
      max_vcpus          = 64
      instance_types     = ["c6i", "m6i"]
      subnet_ids         = ["subnet-aaa"]
      security_group_ids = ["sg-batch"]
    }
  }
  job_queues = {
    default = {
      priority = 50
      compute_environment_order = [
        { order = 2, compute_environment = "fargate-spot" },
        { order = 1, compute_environment = "fargate" },
      ]
    }
  }
}

run "fargate_environments_set_only_fargate_attributes" {
  command = plan

  assert {
    condition     = aws_batch_compute_environment.this["fargate"].name == "test-batch-fargate" && aws_batch_compute_environment.this["fargate"].type == "MANAGED"
    error_message = "Compute environments are MANAGED and named <Environment>-<name>-<key>."
  }

  assert {
    condition = alltrue([for k in ["fargate", "fargate-spot"] : (
      aws_batch_compute_environment.this[k].compute_resources[0].allocation_strategy == null
      && aws_batch_compute_environment.this[k].compute_resources[0].min_vcpus == null
      && aws_batch_compute_environment.this[k].compute_resources[0].instance_role == null
      && length(aws_batch_compute_environment.this[k].compute_resources[0].ec2_configuration) == 0
      && length(aws_batch_compute_environment.this[k].compute_resources[0].launch_template) == 0
    )])
    error_message = "Fargate environments get no allocation strategy, min_vcpus, instance role, AMI or launch template."
  }

  assert {
    condition     = aws_batch_compute_environment.this["fargate-spot"].compute_resources[0].type == "FARGATE_SPOT" && aws_batch_compute_environment.this["fargate-spot"].compute_resources[0].max_vcpus == 512
    error_message = "type and max_vcpus pass through."
  }

  assert {
    condition     = !contains(keys(aws_launch_template.this), "fargate") && !contains(keys(aws_launch_template.this), "fargate-spot")
    error_message = "Fargate environments get no launch template."
  }
}

run "ec2_environment_defaults" {
  command = plan

  assert {
    condition = (
      aws_batch_compute_environment.this["ec2"].compute_resources[0].allocation_strategy == "BEST_FIT_PROGRESSIVE"
      && aws_batch_compute_environment.this["ec2"].compute_resources[0].min_vcpus == 0
      && aws_batch_compute_environment.this["ec2"].compute_resources[0].instance_type == toset(["default_x86_64"])
      && aws_batch_compute_environment.this["ec2"].compute_resources[0].ec2_configuration[0].image_type == "ECS_AL2023"
    )
    error_message = "EC2 defaults: BEST_FIT_PROGRESSIVE, min_vcpus 0, default_x86_64, ECS_AL2023."
  }

  assert {
    condition = (
      aws_batch_compute_environment.this["ec2"].compute_resources[0].launch_template[0].launch_template_id == "lt-0123456789abcdef0"
      && aws_batch_compute_environment.this["ec2"].compute_resources[0].launch_template[0].version == "3"
    )
    error_message = "EC2 environments use their launch template's latest version."
  }

  assert {
    condition = (
      aws_launch_template.this["ec2"].metadata_options[0].http_tokens == "required"
      && aws_launch_template.this["ec2"].metadata_options[0].http_put_response_hop_limit == 1
      && aws_launch_template.this["ec2"].metadata_options[0].http_endpoint == "enabled"
    )
    error_message = "The launch template requires IMDSv2 with hop limit 1."
  }

  assert {
    condition     = aws_batch_compute_environment.this["ec2"].compute_resources[0].tags["Name"] == "test-batch-ec2" && aws_batch_compute_environment.this["ec2"].compute_resources[0].tags["Environment"] == "test"
    error_message = "Instances are tagged with the stack tags and their environment name."
  }

  assert {
    condition = (
      aws_batch_compute_environment.this["ec2"].update_policy[0].job_execution_timeout_minutes == 30
      && aws_batch_compute_environment.this["ec2"].update_policy[0].terminate_jobs_on_update == false
    )
    error_message = "update_policy defaults to a 30-minute job timeout without terminating jobs."
  }

  assert {
    condition     = length(aws_batch_compute_environment.this["spot"].update_policy) == 0
    error_message = "No update_policy unless set."
  }
}

run "spot_environment_defaults_need_no_fleet_role" {
  command = plan

  assert {
    condition = (
      aws_batch_compute_environment.this["spot"].compute_resources[0].allocation_strategy == "SPOT_PRICE_CAPACITY_OPTIMIZED"
      && aws_batch_compute_environment.this["spot"].compute_resources[0].spot_iam_fleet_role == null
      && aws_batch_compute_environment.this["spot"].compute_resources[0].instance_type == toset(["c6i", "m6i"])
    )
    error_message = "SPOT defaults to SPOT_PRICE_CAPACITY_OPTIMIZED without a Spot Fleet role."
  }

  assert {
    condition     = aws_launch_template.this["spot"].metadata_options[0].http_tokens == "required"
    error_message = "SPOT environments also require IMDSv2."
  }
}

run "spot_best_fit_takes_a_fleet_role" {
  command = plan

  variables {
    compute_environments = {
      spot = {
        type                = "SPOT"
        allocation_strategy = "BEST_FIT"
        spot_iam_fleet_role = "arn:aws:iam::123456789012:role/AmazonEC2SpotFleetTaggingRole"
        bid_percentage      = 60
        max_vcpus           = 64
        subnet_ids          = ["subnet-aaa"]
        security_group_ids  = ["sg-batch"]
      }
    }
    job_queues = {}
  }

  assert {
    condition = (
      aws_batch_compute_environment.this["spot"].compute_resources[0].spot_iam_fleet_role == "arn:aws:iam::123456789012:role/AmazonEC2SpotFleetTaggingRole"
      && aws_batch_compute_environment.this["spot"].compute_resources[0].bid_percentage == 60
    )
    error_message = "spot_iam_fleet_role and bid_percentage pass through for SPOT."
  }
}

run "instance_role_is_the_ecs_instance_role_only" {
  command = plan

  assert {
    condition     = length(aws_iam_role.instance) == 1 && aws_iam_role.instance[0].name == "test-batch-instance"
    error_message = "One instance role, <Environment>-<name>-instance, for the EC2/SPOT environments."
  }

  assert {
    condition = (
      jsondecode(aws_iam_role.instance[0].assume_role_policy).Statement[0].Principal.Service == "ec2.amazonaws.com"
      && jsondecode(aws_iam_role.instance[0].assume_role_policy).Statement[0].Action == "sts:AssumeRole"
      && length(jsondecode(aws_iam_role.instance[0].assume_role_policy).Statement) == 1
    )
    error_message = "The instance role trusts ec2.amazonaws.com only."
  }

  assert {
    condition     = aws_iam_role_policy_attachment.instance[0].policy_arn == "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
    error_message = "The instance role carries AmazonEC2ContainerServiceforEC2Role and nothing else."
  }

  assert {
    condition = (
      aws_batch_compute_environment.this["ec2"].compute_resources[0].instance_role == "arn:aws:iam::123456789012:instance-profile/test-batch-instance"
      && aws_batch_compute_environment.this["spot"].compute_resources[0].instance_role == "arn:aws:iam::123456789012:instance-profile/test-batch-instance"
    )
    error_message = "EC2/SPOT environments use the component's instance profile."
  }
}

run "an_own_instance_role_skips_the_component_role" {
  command = plan

  variables {
    compute_environments = {
      ec2 = {
        type               = "EC2"
        instance_role      = "arn:aws:iam::123456789012:instance-profile/custom"
        max_vcpus          = 16
        subnet_ids         = ["subnet-aaa"]
        security_group_ids = ["sg-batch"]
      }
    }
    job_queues = {}
  }

  assert {
    condition     = length(aws_iam_role.instance) == 0 && length(aws_iam_instance_profile.instance) == 0
    error_message = "No instance role when every EC2/SPOT environment names its own."
  }

  assert {
    condition     = aws_batch_compute_environment.this["ec2"].compute_resources[0].instance_role == "arn:aws:iam::123456789012:instance-profile/custom"
    error_message = "instance_role passes through."
  }
}

run "fargate_only_creates_no_iam" {
  command = plan

  variables {
    compute_environments = {
      fargate = {
        max_vcpus          = 16
        subnet_ids         = ["subnet-aaa"]
        security_group_ids = ["sg-batch"]
      }
    }
    job_queues = {}
  }

  assert {
    condition     = length(aws_iam_role.instance) == 0 && length(aws_launch_template.this) == 0
    error_message = "Fargate-only instances create no IAM role and no launch template."
  }

  assert {
    condition     = aws_batch_compute_environment.this["fargate"].compute_resources[0].type == "FARGATE"
    error_message = "type defaults to FARGATE."
  }
}

run "queues_resolve_keys_in_order_and_pass_arns_through" {
  command = plan

  variables {
    job_queues = {
      default = {
        priority = 50
        compute_environment_order = [
          { order = 2, compute_environment = "fargate-spot" },
          { order = 1, compute_environment = "fargate" },
        ]
      }
      gpu = {
        state = "DISABLED"
        compute_environment_order = [
          { order = 1, compute_environment = "ec2" },
          { order = 2, compute_environment = "arn:aws:batch:us-east-1:123456789012:compute-environment/shared-gpu" },
        ]
      }
    }
  }

  assert {
    condition     = aws_batch_job_queue.this["default"].name == "test-batch-default" && aws_batch_job_queue.this["default"].priority == 50 && aws_batch_job_queue.this["default"].state == "ENABLED"
    error_message = "Queues are named <Environment>-<name>-<key>, with priority and state."
  }

  assert {
    condition = (
      { for o in aws_batch_job_queue.this["default"].compute_environment_order : o.order => o.compute_environment } == {
        1 = "arn:aws:batch:us-east-1:123456789012:compute-environment/test-batch-fargate"
        2 = "arn:aws:batch:us-east-1:123456789012:compute-environment/test-batch-fargate-spot"
      }
    )
    error_message = "compute_environment_order keys resolve to this instance's compute environment ARNs, keeping their order."
  }

  assert {
    condition = (
      { for o in aws_batch_job_queue.this["gpu"].compute_environment_order : o.order => o.compute_environment } == {
        1 = "arn:aws:batch:us-east-1:123456789012:compute-environment/test-batch-ec2"
        2 = "arn:aws:batch:us-east-1:123456789012:compute-environment/shared-gpu"
      }
    )
    error_message = "An external compute environment ARN passes through."
  }

  assert {
    condition     = aws_batch_job_queue.this["gpu"].priority == 1 && aws_batch_job_queue.this["gpu"].state == "DISABLED"
    error_message = "priority defaults to 1; state passes through."
  }

  assert {
    condition     = length(aws_batch_scheduling_policy.this) == 0 && aws_batch_job_queue.this["default"].scheduling_policy_arn == null
    error_message = "No scheduling policy (FIFO) unless fair_share_policy is set."
  }

  assert {
    condition     = toset(keys(output.job_queue_arns)) == toset(["default", "gpu"]) && output.compute_environment_arns["fargate"] == "arn:aws:batch:us-east-1:123456789012:compute-environment/test-batch-fargate"
    error_message = "job_queue_arns and compute_environment_arns are keyed maps."
  }
}

run "fair_share_policy_creates_a_scheduling_policy" {
  command = plan

  variables {
    job_queues = {
      shared = {
        compute_environment_order = [{ order = 1, compute_environment = "fargate" }]
        fair_share_policy = {
          compute_reservation = 10
          share_decay_seconds = 3600
          share_distribution = [
            { share_identifier = "teamA", weight_factor = 0.5 },
            { share_identifier = "teamB" },
          ]
        }
      }
    }
  }

  assert {
    condition = (
      aws_batch_scheduling_policy.this["shared"].name == "test-batch-shared"
      && aws_batch_scheduling_policy.this["shared"].fair_share_policy[0].compute_reservation == 10
      && length(aws_batch_scheduling_policy.this["shared"].fair_share_policy[0].share_distribution) == 2
    )
    error_message = "fair_share_policy creates a scheduling policy named like its queue."
  }
}

run "disabled_creates_nothing" {
  command = plan

  variables {
    enabled = false
  }

  assert {
    condition = (
      length(aws_batch_compute_environment.this) == 0 && length(aws_batch_job_queue.this) == 0
      && length(aws_iam_role.instance) == 0 && length(aws_launch_template.this) == 0
      && output.job_queue_arns == {}
    )
    error_message = "enabled = false creates no resources."
  }
}

# Negative validations.

run "fargate_rejects_instance_types" {
  command = plan

  variables {
    compute_environments = {
      fargate = {
        max_vcpus          = 16
        instance_types     = ["c6i"]
        subnet_ids         = ["subnet-aaa"]
        security_group_ids = ["sg-batch"]
      }
    }
    job_queues = {}
  }

  expect_failures = [var.compute_environments]
}

run "fargate_rejects_min_vcpus" {
  command = plan

  variables {
    compute_environments = {
      fargate = {
        type               = "FARGATE_SPOT"
        max_vcpus          = 16
        min_vcpus          = 0
        subnet_ids         = ["subnet-aaa"]
        security_group_ids = ["sg-batch"]
      }
    }
    job_queues = {}
  }

  expect_failures = [var.compute_environments]
}

run "fargate_requires_max_vcpus" {
  command = plan

  variables {
    compute_environments = {
      fargate = {
        subnet_ids         = ["subnet-aaa"]
        security_group_ids = ["sg-batch"]
      }
    }
    job_queues = {}
  }

  expect_failures = [var.compute_environments]
}

run "ec2_rejects_spot_allocation_strategies" {
  command = plan

  variables {
    compute_environments = {
      ec2 = {
        type                = "EC2"
        allocation_strategy = "SPOT_CAPACITY_OPTIMIZED"
        max_vcpus           = 16
        subnet_ids          = ["subnet-aaa"]
        security_group_ids  = ["sg-batch"]
      }
    }
    job_queues = {}
  }

  expect_failures = [var.compute_environments]
}

run "spot_best_fit_requires_a_fleet_role" {
  command = plan

  variables {
    compute_environments = {
      spot = {
        type                = "SPOT"
        allocation_strategy = "BEST_FIT"
        max_vcpus           = 16
        subnet_ids          = ["subnet-aaa"]
        security_group_ids  = ["sg-batch"]
      }
    }
    job_queues = {}
  }

  expect_failures = [var.compute_environments]
}

run "update_policy_rejects_best_fit" {
  command = plan

  variables {
    compute_environments = {
      ec2 = {
        type                = "EC2"
        allocation_strategy = "BEST_FIT"
        update_policy       = {}
        max_vcpus           = 16
        subnet_ids          = ["subnet-aaa"]
        security_group_ids  = ["sg-batch"]
      }
    }
    job_queues = {}
  }

  expect_failures = [var.compute_environments]
}

run "min_vcpus_above_max_is_rejected" {
  command = plan

  variables {
    compute_environments = {
      ec2 = {
        type               = "EC2"
        min_vcpus          = 32
        max_vcpus          = 16
        subnet_ids         = ["subnet-aaa"]
        security_group_ids = ["sg-batch"]
      }
    }
    job_queues = {}
  }

  expect_failures = [var.compute_environments]
}

run "queue_rejects_an_unknown_compute_environment_key" {
  command = plan

  variables {
    job_queues = {
      default = {
        compute_environment_order = [{ order = 1, compute_environment = "missing" }]
      }
    }
  }

  expect_failures = [var.job_queues]
}

run "queue_rejects_mixing_fargate_and_ec2" {
  command = plan

  variables {
    job_queues = {
      default = {
        compute_environment_order = [
          { order = 1, compute_environment = "fargate" },
          { order = 2, compute_environment = "ec2" },
        ]
      }
    }
  }

  expect_failures = [var.job_queues]
}

run "queue_rejects_duplicate_orders" {
  command = plan

  variables {
    job_queues = {
      default = {
        compute_environment_order = [
          { order = 1, compute_environment = "fargate" },
          { order = 1, compute_environment = "fargate-spot" },
        ]
      }
    }
  }

  expect_failures = [var.job_queues]
}

run "queue_rejects_more_than_three_compute_environments" {
  command = plan

  variables {
    job_queues = {
      default = {
        compute_environment_order = [
          { order = 1, compute_environment = "fargate" },
          { order = 2, compute_environment = "fargate-spot" },
          { order = 3, compute_environment = "arn:aws:batch:us-east-1:123456789012:compute-environment/a" },
          { order = 4, compute_environment = "arn:aws:batch:us-east-1:123456789012:compute-environment/b" },
        ]
      }
    }
  }

  expect_failures = [var.job_queues]
}

run "instance_role_rejects_a_bare_profile_name" {
  command = plan

  variables {
    compute_environments = {
      ec2 = {
        type               = "EC2"
        instance_role      = "ecsInstanceRole"
        max_vcpus          = 16
        subnet_ids         = ["subnet-aaa"]
        security_group_ids = ["sg-batch"]
      }
    }
    job_queues = {}
  }

  expect_failures = [var.compute_environments]
}

run "instance_role_rejects_a_role_arn" {
  command = plan

  variables {
    compute_environments = {
      ec2 = {
        type               = "EC2"
        instance_role      = "arn:aws:iam::123456789012:role/ecsInstanceRole"
        max_vcpus          = 16
        subnet_ids         = ["subnet-aaa"]
        security_group_ids = ["sg-batch"]
      }
    }
    job_queues = {}
  }

  expect_failures = [var.compute_environments]
}

run "null_subnet_ids_is_rejected" {
  command = plan

  variables {
    compute_environments = {
      fargate = {
        max_vcpus          = 16
        subnet_ids         = null
        security_group_ids = ["sg-batch"]
      }
    }
    job_queues = {}
  }

  expect_failures = [var.compute_environments]
}

run "null_compute_environment_order_is_rejected" {
  command = plan

  variables {
    job_queues = {
      default = {
        compute_environment_order = null
      }
    }
  }

  expect_failures = [var.job_queues]
}
