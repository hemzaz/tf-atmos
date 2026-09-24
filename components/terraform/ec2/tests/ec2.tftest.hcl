# Mock-provider tests: no AWS credentials, no network. Run from the component
# directory with `terraform init -backend=false && terraform test`.

mock_provider "aws" {
  mock_data "aws_ami" {
    defaults = {
      id = "ami-0123456789abcdef0"
    }
  }

  mock_resource "aws_launch_template" {
    defaults = {
      id = "lt-0123456789abcdef0"
    }
  }

  mock_resource "aws_security_group" {
    defaults = {
      id = "sg-0123456789abcdef0"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock"
    }
  }
}

mock_provider "tls" {}

variables {
  region     = "eu-west-2"
  name       = "bastion"
  vpc_id     = "vpc-0123456789abcdef0"
  subnet_ids = ["subnet-0a1b2c3d"]
  subnet     = "subnet-4e5f6a7b"
  tags = {
    Environment = "testenv-01"
  }
  instance_type = "t3.small"
  ssh_key_pair  = "bastion-ssh-key"
}

run "names_follow_the_prefix" {
  command = apply

  assert {
    condition     = output.name == "testenv-01-bastion" && aws_instance.default[0].tags["Name"] == "testenv-01-bastion"
    error_message = "The instance must be named <Environment>-<name>."
  }

  assert {
    condition     = aws_security_group.default[0].name == "testenv-01-bastion-sg" && aws_iam_role.default[0].name == "testenv-01-bastion-role" && aws_iam_instance_profile.default[0].name == "testenv-01-bastion-profile"
    error_message = "Security group, role and profile names must be <Environment>-<name>-{sg,role,profile}."
  }

  assert {
    condition     = length(aws_iam_role.default[0].name) <= 64
    error_message = "The IAM role name must fit 64 characters."
  }

  assert {
    condition     = aws_instance.default[0].subnet_id == "subnet-4e5f6a7b"
    error_message = "subnet wins over subnet_ids."
  }

  # Cloud Posse's ec2-instance has no launch template.
  assert {
    condition     = length(aws_launch_template.default) == 0 && length(aws_instance.from_launch_template) == 0
    error_message = "No launch template by default."
  }
}

run "outputs_have_the_consumer_formats" {
  command = apply

  # app-server reads ssh_key_pair as its own key pair: the key the instance
  # launched with, a plain name.
  assert {
    condition     = output.ssh_key_pair == "bastion-ssh-key"
    error_message = "ssh_key_pair must be the key the instance launched with."
  }

  # staging uses security_group_id as a list item, so it must be a string.
  assert {
    condition     = can(regex("^sg-", output.security_group_id))
    error_message = "security_group_id must be a scalar security group ID."
  }

  assert {
    condition     = output.security_group_ids == tolist(["sg-0123456789abcdef0"])
    error_message = "security_group_ids lists the instance's own group first."
  }

  assert {
    condition     = output.id == aws_instance.default[0].id
    error_message = "id must be the standalone instance's."
  }
}

run "from_template_does_not_duplicate_the_instance" {
  command = apply

  variables {
    enable_launch_templates         = true
    create_instances_from_templates = true
  }

  assert {
    condition     = length(aws_instance.default) == 0 && length(aws_instance.from_launch_template) == 1
    error_message = "With create_instances_from_templates exactly one instance exists, from the template."
  }

  assert {
    condition     = output.id == aws_instance.from_launch_template[0].id
    error_message = "id must come from the launch-template instance."
  }

  assert {
    condition     = aws_launch_template.default[0].iam_instance_profile[0].name == "testenv-01-bastion-profile"
    error_message = "An instance launched from the template must get the instance profile."
  }

  assert {
    condition     = aws_launch_template.default[0].key_name == "bastion-ssh-key"
    error_message = "The template must carry the key pair."
  }

  assert {
    condition     = aws_instance.from_launch_template[0].root_block_device[0].encrypted == true
    error_message = "The launch-template instance's root volume is encrypted too."
  }
}

run "template_alone_keeps_the_standalone_instance" {
  command = plan

  variables {
    enable_launch_templates = true
  }

  assert {
    condition     = length(aws_instance.default) == 1 && length(aws_instance.from_launch_template) == 0 && length(aws_launch_template.default) == 1
    error_message = "enable_launch_templates alone adds the template and keeps one standalone instance."
  }
}

run "from_template_needs_the_template" {
  command = plan

  variables {
    create_instances_from_templates = true
  }

  expect_failures = [var.create_instances_from_templates]
}

# A plan, not an apply: tls_private_key is prevent_destroy, so an applied key
# would block every later run that drops it.
run "generated_keys_are_per_instance" {
  command = plan

  variables {
    name            = "app-server"
    ssh_key_pair    = null
    create_ssh_keys = true
  }

  assert {
    condition     = aws_key_pair.generated[0].key_name == "testenv-01-app-server-ec2-ssh-key"
    error_message = "A generated key pair is named after its instance."
  }

  assert {
    condition     = aws_secretsmanager_secret.ssh_key[0].name == "ssh-key/testenv-01/app-server"
    error_message = "A generated key's secret is named after its instance."
  }

  assert {
    condition     = output.ssh_key_pair == "testenv-01-app-server-ec2-ssh-key"
    error_message = "ssh_key_pair must be the generated key."
  }
}

# The stacks' bastions: no ssh_key_pair, so the component generates the key
# (ED25519 by default), stores it KMS-encrypted, and launches with it.
run "bastion_generates_its_own_key" {
  command = plan

  variables {
    ssh_key_pair              = null
    create_ssh_keys           = true
    ssh_key_secret_kms_key_id = "arn:aws:kms:eu-west-2:123456789012:key/11111111-2222-3333-4444-555555555555"
  }

  assert {
    condition     = tls_private_key.ssh_key[0].algorithm == "ED25519"
    error_message = "Generated keys default to ED25519."
  }

  assert {
    condition     = aws_key_pair.generated[0].key_name == "testenv-01-bastion-ec2-ssh-key" && aws_secretsmanager_secret.ssh_key[0].name == "ssh-key/testenv-01/bastion"
    error_message = "The bastion's key and secret are named after it."
  }

  assert {
    condition     = aws_secretsmanager_secret.ssh_key[0].kms_key_id == "arn:aws:kms:eu-west-2:123456789012:key/11111111-2222-3333-4444-555555555555"
    error_message = "The private key's secret is encrypted with the given KMS key."
  }

  # app-server reads this as its ssh_key_pair.
  assert {
    condition     = output.ssh_key_pair == "testenv-01-bastion-ec2-ssh-key" && aws_instance.default[0].key_name == output.ssh_key_pair
    error_message = "ssh_key_pair must be the generated key the instance launched with."
  }

  # Two instances in one stack never share a key (the old global key did, so
  # the second apply failed): compared with app-server's run above.
  assert {
    condition     = output.ssh_key_pair != run.generated_keys_are_per_instance.ssh_key_pair
    error_message = "Each instance must get its own key pair."
  }

  assert {
    condition     = aws_secretsmanager_secret.ssh_key[0].recovery_window_in_days == 30
    error_message = "A deleted private-key secret stays recoverable for 30 days by default."
  }
}

# An apply, so the secret's contents are known: the OpenSSH format is stored
# (ED25519 PEM is PKCS#8, which many OpenSSH builds reject) next to the PEM.
run "secret_holds_the_openssh_private_key" {
  command = apply

  variables {
    ssh_key_pair    = null
    create_ssh_keys = true
  }

  assert {
    condition = alltrue([
      for k in ["private_key_openssh", "private_key_pem", "public_key_openssh", "key_name"] :
      contains(keys(jsondecode(aws_secretsmanager_secret_version.ssh_key[0].secret_string)), k)
    ])
    error_message = "The secret must hold private_key_openssh, private_key_pem, public_key_openssh and key_name."
  }

  assert {
    condition     = jsondecode(aws_secretsmanager_secret_version.ssh_key[0].secret_string).private_key_openssh == tls_private_key.ssh_key[0].private_key_openssh
    error_message = "private_key_openssh must be the generated key's OpenSSH form."
  }
}

run "prod_name_repeating_the_environment_is_rejected" {
  command = plan

  variables {
    name = "production-bastion"
    tags = {
      Environment = "production"
    }
  }

  expect_failures = [var.name]
}

run "prod_requires_termination_protection" {
  command = plan

  variables {
    environment = "prod"
  }

  expect_failures = [var.disable_api_termination]
}

# Keyless (SSM-only) instances are allowed, as in Cloud Posse's aws-ec2-instance.
run "keyless_instance_is_allowed" {
  command   = plan
  state_key = "keyless_instance_is_allowed"

  variables {
    ssh_key_pair = null
  }

  # key_name is Optional+Computed, so an unset one plans as unknown. What the
  # component decides is checked: the instance plans (no key precondition),
  # and no key is generated or looked up.
  assert {
    condition     = length(aws_instance.default) == 1 && length(aws_key_pair.generated) == 0 && length(data.aws_key_pair.existing) == 0
    error_message = "Without ssh_key_pair or create_ssh_keys the instance launches without a key."
  }
}

run "empty_key_name_is_treated_as_unset" {
  command   = plan
  state_key = "empty_key_name_is_treated_as_unset"

  variables {
    ssh_key_pair = ""
  }

  assert {
    condition     = length(aws_instance.default) == 1 && length(aws_key_pair.generated) == 0 && length(data.aws_key_pair.existing) == 0
    error_message = "ssh_key_pair = \"\" must behave as null: no key lookup (an empty name would fail it) and no generated key."
  }
}

run "empty_key_name_with_generation_generates" {
  command = plan

  variables {
    ssh_key_pair    = ""
    create_ssh_keys = true
  }

  assert {
    condition     = aws_instance.default[0].key_name == "testenv-01-bastion-ec2-ssh-key"
    error_message = "ssh_key_pair = \"\" with create_ssh_keys must generate a key."
  }
}

run "hardening_defaults" {
  command = plan

  assert {
    condition = (
      aws_instance.default[0].metadata_options[0].http_tokens == "required" &&
      aws_instance.default[0].metadata_options[0].http_put_response_hop_limit == 1 &&
      aws_instance.default[0].metadata_options[0].instance_metadata_tags == "disabled"
    )
    error_message = "IMDSv2 is required with a hop limit of 1, and tags are not exposed through IMDS."
  }

  assert {
    condition     = aws_instance.default[0].root_block_device[0].encrypted == true
    error_message = "The standalone instance's root volume is encrypted."
  }

  assert {
    condition     = aws_instance.default[0].monitoring == true
    error_message = "Detailed monitoring is on by default (Cloud Posse's default)."
  }

  # Egress is unrestricted by policy: Cloud Posse's default, all outbound.
  assert {
    condition = anytrue([
      for e in aws_security_group.default[0].egress : e.protocol == "-1" && contains(e.cidr_blocks, "0.0.0.0/0")
    ])
    error_message = "The default egress rule allows all outbound traffic."
  }

  assert {
    condition     = length(data.aws_ami.default) == 1
    error_message = "With no ami, the latest Amazon Linux 2023 image is looked up."
  }
}

run "given_ami_skips_the_lookup" {
  command   = plan
  state_key = "given_ami_skips_the_lookup"

  variables {
    ami = "ami-0abcdef1234567890"
  }

  assert {
    condition     = length(data.aws_ami.default) == 0 && aws_instance.default[0].ami == "ami-0abcdef1234567890"
    error_message = "A given ami is used as is, without the AMI lookup."
  }
}

run "prod_standalone_instance_is_termination_protected" {
  command = plan

  variables {
    environment             = "prod"
    disable_api_termination = true
  }

  assert {
    condition     = aws_instance.default[0].disable_api_termination == true
    error_message = "disable_api_termination must reach the standalone instance."
  }
}

run "ingress_open_to_everywhere_is_rejected" {
  command = plan

  variables {
    allowed_ingress_rules = [{
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ["10.0.0.0/8", "0.0.0.0/0"]
    }]
  }

  expect_failures = [var.allowed_ingress_rules]
}

run "open_egress_is_allowed" {
  command = plan

  variables {
    allowed_egress_rules = [{
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }]
  }

  assert {
    condition     = length(aws_security_group.default[0].egress) == 1
    error_message = "Egress to 0.0.0.0/0 is allowed by policy."
  }
}

run "recovery_window_out_of_range_is_rejected" {
  command = plan

  variables {
    ssh_key_secret_recovery_window_in_days = 5
  }

  expect_failures = [var.ssh_key_secret_recovery_window_in_days]
}

run "malformed_kms_key_is_rejected" {
  command = plan

  variables {
    ssh_key_secret_kms_key_id = "not-a-key"
  }

  expect_failures = [var.ssh_key_secret_kms_key_id]
}

run "disabled_creates_nothing" {
  command = apply

  variables {
    enabled = false
  }

  assert {
    condition     = length(aws_instance.default) == 0 && length(aws_security_group.default) == 0 && length(aws_iam_role.default) == 0
    error_message = "enabled = false must create nothing."
  }

  assert {
    condition     = output.id == null && output.ssh_key_pair == null && output.security_group_id == null && output.name == null
    error_message = "enabled = false must output nulls."
  }
}
