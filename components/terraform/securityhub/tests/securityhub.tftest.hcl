# Mock-provider tests: no AWS credentials, no network. Run from the component
# directory with `terraform init -backend=false && terraform test`.

mock_provider "aws" {}

variables {
  region    = "us-east-2"
  standards = ["pci-dss/v/3.2.1"]
  tags = {
    Environment = "ue2"
  }
}

run "nothing_disabled_by_default" {
  command = plan

  assert {
    condition     = length(aws_securityhub_standards_control_association.disabled) == 0
    error_message = "No control is disabled unless disabled_security_controls lists it."
  }
}

run "global_resource_controls_are_disabled_per_standard" {
  command = plan

  variables {
    disabled_security_controls = {
      "cis-aws-foundations-benchmark/v/1.2.0" = ["IAM.1"]
      "pci-dss/v/3.2.1"                       = ["IAM.1", "IAM.19"]
    }
  }

  assert {
    condition = (
      length(aws_securityhub_standards_control_association.disabled) == 3
      && aws_securityhub_standards_control_association.disabled["cis-aws-foundations-benchmark/v/1.2.0|IAM.1"].standards_arn == "arn:aws:securityhub:::ruleset/cis-aws-foundations-benchmark/v/1.2.0"
      && aws_securityhub_standards_control_association.disabled["pci-dss/v/3.2.1|IAM.19"].standards_arn == "arn:aws:securityhub:us-east-2::standards/pci-dss/v/3.2.1"
      && aws_securityhub_standards_control_association.disabled["pci-dss/v/3.2.1|IAM.19"].association_status == "DISABLED"
    )
    error_message = "Each (standard, control) pair must become one DISABLED association with the standard's ARN."
  }
}

run "an_unsubscribed_standard_is_rejected" {
  command = plan

  variables {
    disabled_security_controls = {
      "nist-800-53/v/5.0.0" = ["IAM.1"]
    }
  }

  expect_failures = [var.disabled_security_controls]
}

run "a_malformed_control_id_is_rejected" {
  command = plan

  variables {
    disabled_security_controls = {
      "pci-dss/v/3.2.1" = ["PCI.IAM.1"]
    }
  }

  expect_failures = [var.disabled_security_controls]
}
